#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3
"""Merge validated, bot-authored fork update MRs — and nothing else.

Replaces the GitHub ``auto-merge.yml`` flow for the GitLab-hosted fork.
An MR is only ever merged when *all* of the following hold:

* it is authored by the pipeline's bot user (resolved from GL_TOKEN);
* its source branch is ``update/<package>`` and it targets the default
  branch;
* it carries the ``automated`` label and is neither draft nor WIP;
* validation is green for its head SHA: either the GitLab
  ``head_pipeline`` succeeded, or every Woodpecker commit status
  (``ci/woodpecker/…``, reported by the GitLab forge) succeeded — at
  least one of the two must exist, otherwise the MR waits;
* the head SHA is unchanged: the merge request is re-fetched right
  before merging and the merge call pins that SHA server-side, so any
  push between check and merge aborts the merge.

Human-authored or arbitrary pending MRs are never touched.
"""

from __future__ import annotations

import argparse
import logging
import os
import re
import time
from enum import StrEnum
from typing import Any

try:
    from .gitlab_api import (
        GitLabApi,
        GitLabApiError,
        resolve_config,
        resolve_default_branch,
    )
except ImportError:  # executed as a script
    from gitlab_api import (
        GitLabApi,
        GitLabApiError,
        resolve_config,
        resolve_default_branch,
    )

log = logging.getLogger(__name__)

UPDATE_BRANCH_PREFIX = "update/"
REQUIRED_LABEL = "automated"
REQUIRED_MERGE_STATUS = ("mergeable", "ci_passing")

PENDING_PIPELINE_STATES = (
    "created",
    "waiting_for_resource",
    "preparing",
    "pending",
    "running",
    "manual",
)
FAILED_PIPELINE_STATES = ("failed", "canceled", "skipped")

PENDING_STATUS_STATES = ("pending", "running")
FAILED_STATUS_STATES = ("failed", "error", "canceled")

WOODPECKER_CONTEXT_PREFIX = "ci/woodpecker/"

NOT_MERGEABLE_HTTP = (400, 405, 406, 409)


class Validation(StrEnum):
    """Outcome of checking an MR's validation evidence."""

    READY = "ready"
    PENDING = "pending"
    FAILED = "failed"


def eligible(
    mr: dict[str, Any],
    *,
    bot_username: str,
    default_branch: str,
) -> tuple[bool, str]:
    """Whether an MR belongs to the automated fork update flow."""
    author = (mr.get("author") or {}).get("username", "")
    if author != bot_username:
        return False, f"author {author!r} is not the bot {bot_username!r}"
    source = mr.get("source_branch", "")
    if not re.fullmatch(r"update/[A-Za-z0-9][A-Za-z0-9._+-]*", source):
        return False, f"source branch {source!r} is not {UPDATE_BRANCH_PREFIX}*"
    if mr.get("target_branch") != default_branch:
        return False, f"target branch {mr.get('target_branch')!r} is not the default"
    if mr.get("source_project_id") != mr.get("target_project_id"):
        return False, "source branch belongs to a different project"
    if not {REQUIRED_LABEL, "dependencies"}.issubset(mr.get("labels") or []):
        return False, f"missing {REQUIRED_LABEL!r} label"
    if mr.get("draft") or mr.get("work_in_progress"):
        return False, "MR is a draft"
    return True, "bot update MR"


def _woodpecker_states(statuses: list[dict[str, Any]]) -> list[str]:
    """States of the Woodpecker-reported commit statuses for one SHA."""
    return [
        str(status.get("status", ""))
        for status in statuses
        if str(status.get("name", "")).startswith(WOODPECKER_CONTEXT_PREFIX)
    ]


def _is_mr_pipeline(pipeline: dict[str, Any], *, api: GitLabApi, project: str) -> bool:
    """External-status-only pipelines do not prove our MR checks ran."""
    details = pipeline
    if "source" not in details and pipeline.get("id"):
        details = api.request("GET", f"/projects/{project}/pipelines/{pipeline['id']}")
    return details.get("source") == "merge_request_event"


def validation_state(
    mr: dict[str, Any],
    *,
    api: GitLabApi,
    project: str,
) -> tuple[Validation, str]:
    """Check the MR's validation evidence for its head SHA."""
    sha = mr.get("sha") or ""
    pipeline = mr.get("head_pipeline") or None
    gitlab_ok = False

    if pipeline:
        status = str(pipeline.get("status", ""))
        if status in PENDING_PIPELINE_STATES:
            return Validation.PENDING, f"GitLab pipeline {status}"
        if status in FAILED_PIPELINE_STATES:
            return Validation.FAILED, f"GitLab pipeline {status}"
        if status == "success" and pipeline.get("sha") == sha:
            gitlab_ok = _is_mr_pipeline(pipeline, api=api, project=project)

    statuses = list(
        api.paginate(f"/projects/{project}/repository/commits/{sha}/statuses")
    )
    woodpecker = _woodpecker_states(statuses if isinstance(statuses, list) else [])
    woodpecker_ok = False
    # A maintenance/unrelated workflow is not MR validation evidence.
    validation_context = os.environ.get(
        "WOODPECKER_VALIDATION_CONTEXT", "ci/woodpecker/pr/validate-mr"
    )
    has_validation = any(
        status.get("name") == validation_context for status in statuses
    )
    if woodpecker:
        if any(state in PENDING_STATUS_STATES for state in woodpecker):
            return Validation.PENDING, "Woodpecker status still running"
        if any(state in FAILED_STATUS_STATES for state in woodpecker):
            return Validation.FAILED, "Woodpecker status failed"
        if has_validation and all(state == "success" for state in woodpecker):
            woodpecker_ok = True

    if gitlab_ok or woodpecker_ok:
        return Validation.READY, "validation green"
    return Validation.PENDING, "no validation evidence for head SHA yet"


def merge_status_ok(mr: dict[str, Any]) -> bool:
    """Whether GitLab reports the MR as currently mergeable."""
    detailed = mr.get("detailed_merge_status")
    if detailed:
        return detailed in REQUIRED_MERGE_STATUS
    return mr.get("merge_status") == "can_be_merged"


def merge_candidate(
    mr_iid: int,
    *,
    api: GitLabApi,
    project: str,
    observed_sha: str,
    bot: str,
    default_branch: str,
) -> tuple[bool, str]:
    """Re-fetch, guard, and merge one MR; returns (merged, reason)."""
    fresh = api.request("GET", f"/projects/{project}/merge_requests/{mr_iid}")
    fresh_sha = fresh.get("sha") or ""
    if fresh_sha != observed_sha:
        return False, f"head SHA moved {observed_sha[:8]} -> {fresh_sha[:8]}"
    if fresh.get("state") != "opened":
        return False, f"MR state is {fresh.get('state')}"
    ok, reason = eligible(fresh, bot_username=bot, default_branch=default_branch)
    if not ok:
        return False, reason
    state, reason = validation_state(fresh, api=api, project=project)
    if state is not Validation.READY:
        return False, reason
    if not merge_status_ok(fresh):
        return False, f"merge status {fresh.get('detailed_merge_status')!r}"

    try:
        api.request(
            "PUT",
            f"/projects/{project}/merge_requests/{mr_iid}/merge",
            json_body={
                # Server-side head-SHA guard: GitLab refuses to merge if
                # the MR head moved away from this SHA.
                "sha": fresh_sha,
                "squash": True,
                "remove_source_branch": True,
            },
        )
    except GitLabApiError as error:
        if error.status in NOT_MERGEABLE_HTTP:
            return False, f"GitLab refused merge: HTTP {error.status}"
        raise
    return True, f"merged {fresh_sha[:8]}"


def bot_username(api: GitLabApi, environ: dict[str, str]) -> str:
    """Resolve the bot username: explicit override or the token's user."""
    override = environ.get("CI_BOT_USERNAME", "").strip()
    if override:
        return override
    user = api.request("GET", "/user")
    return str(user.get("username", ""))


def sweep_once(
    *,
    api: GitLabApi,
    project: str,
    default_branch: str,
    bot: str,
    merged: list[str],
    refused: dict[str, str],
) -> list[str]:
    """One polling pass: merge what is ready; return still-waiting MRs."""
    mrs = list(
        api.paginate(
            f"/projects/{project}/merge_requests",
            params={"state": "opened", "target_branch": default_branch},
        )
    )
    waiting: list[str] = []
    for summary in sorted(mrs, key=lambda item: item.get("created_at", "")):
        ok, _why = eligible(summary, bot_username=bot, default_branch=default_branch)
        if not ok:
            continue
        # List summaries need not include head_pipeline; inspect MR details.
        mr = api.request("GET", f"/projects/{project}/merge_requests/{summary['iid']}")
        ok, _why = eligible(mr, bot_username=bot, default_branch=default_branch)
        if not ok:
            continue
        title = f"!{mr['iid']} {mr.get('title', '')}"

        state, detail = validation_state(mr, api=api, project=project)
        if state is Validation.PENDING:
            log.info("[wait] %s: %s", title, detail)
            waiting.append(title)
            continue
        if state is Validation.FAILED:
            log.info("[skip] %s: %s", title, detail)
            refused[title] = detail
            continue

        try:
            done, result = merge_candidate(
                mr["iid"],
                api=api,
                project=project,
                observed_sha=mr.get("sha", ""),
                bot=bot,
                default_branch=default_branch,
            )
        except GitLabApiError:
            log.exception("[error] %s", title)
            raise
        if done:
            log.info("[merged] %s: %s", title, result)
            merged.append(title)
            refused.pop(title, None)
        else:
            log.info("[retry] %s: %s", title, result)
            refused[title] = result
            waiting.append(title)
    return waiting


def main() -> None:
    """Poll eligible MRs and merge those with green, SHA-pinned validation."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()

    gitlab = resolve_config()
    api = gitlab.api()
    project = gitlab.project_url_encoded
    default_branch = resolve_default_branch(api=api, project_path_encoded=project)
    bot = bot_username(api, dict(os.environ))
    timeout = int(os.environ.get("MERGE_WAIT_TIMEOUT", "1800"))
    interval = int(os.environ.get("MERGE_POLL_INTERVAL", "60"))

    log.info("Merging bot update MRs as @%s (target: %s)", bot, default_branch)
    merged: list[str] = []
    refused: dict[str, str] = {}
    deadline = time.monotonic() + timeout

    while True:
        waiting = sweep_once(
            api=api,
            project=project,
            default_branch=default_branch,
            bot=bot,
            merged=merged,
            refused=refused,
        )
        if not waiting:
            break
        if time.monotonic() >= deadline:
            log.warning(
                "timed out after %ss waiting for validation of: %s",
                timeout,
                ", ".join(waiting),
            )
            break
        log.info("%s MR(s) still pending; retrying in %ss", len(waiting), interval)
        time.sleep(interval)

    log.info("=== Merge summary: %d merged, %d refused ===", len(merged), len(refused))
    for title, reason in sorted(refused.items()):
        log.info("  refused: %s (%s)", title, reason)


if __name__ == "__main__":
    main()
