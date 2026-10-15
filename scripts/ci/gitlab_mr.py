"""Publish fork package updates as GitLab merge requests.

Mirrors ``.github/ci/create_pr.py`` (kept unmodified, upstream-owned):

* path confinement: the updater's work tree is untrusted, so only the
  updated package's directory (plus its update-companions) may differ
  from the base branch;
* pristine publish: the update branch is rebuilt in a fresh clone that
  the updater never touched, then force-pushed;
* MR create-or-update keyed on the ``update/<package>`` source branch.

Additions over the GitHub flow: a downgrade guard (the fork updater
stack has no built-in protection against version regressions) and the
GitLab MR API instead of ``gh``.
"""

from __future__ import annotations

import logging
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import urlparse

try:
    from .gitlab_api import GitLabApi, resolve_config
except ImportError:  # executed as a script
    from gitlab_api import GitLabApi, resolve_config

log = logging.getLogger(__name__)

BOT_NAME = "llm-agents-bot"

PRERELEASE_TOKENS = ("dev", "alpha", "beta", "rc", "pre", "nightly", "snapshot")

# Digits and letter runs; separators (dots, dashes, underscores) split them,
# so "1.2.0-rc.1" -> [1, 2, 0, "rc", 1] and "rc" matches the
# pre-release tokens below.
VERSION_SEGMENT = re.compile(r"\d+|[a-zA-Z]+")

# Paths an update is allowed to touch, relative to the repository root.


def _segments(version: str) -> list[int | str]:
    """Split a version string into comparable integer/text segments."""
    return [
        int(token) if token.isdigit() else token.lower()
        for token in VERSION_SEGMENT.findall(version)
        if token
    ]


def is_downgrade(current: str, new: str) -> bool:
    """Whether ``new`` orders strictly below ``current``.

    Minimal guard for a fork updater stack without regression
    protection: numeric segments compare numerically, text segments
    lexically, and a prefix-extended side is greater unless the extra
    segments start with a pre-release marker (so 1.2.0-rc.1 < 1.2.0).
    """
    if current == new:
        return False
    current_segments = _segments(current)
    new_segments = _segments(new)
    for left, right in zip(current_segments, new_segments, strict=False):
        if left == right:
            continue
        if isinstance(left, int) and isinstance(right, int):
            return left > right
        if isinstance(left, int) != isinstance(right, int):
            # Numeric segments order above arbitrary text suffixes.
            return isinstance(left, int)
        return str(left) > str(right)
    if len(current_segments) == len(new_segments):
        return False
    if len(current_segments) > len(new_segments):
        longer, longer_is_current = current_segments, True
    else:
        longer, longer_is_current = new_segments, False
    shorter_len = min(len(current_segments), len(new_segments))
    extra = longer[shorter_len:]
    extended_is_prerelease = bool(extra) and str(extra[0]) in PRERELEASE_TOKENS
    # The side carrying extra segments is greater, unless those extra
    # segments mark it as a pre-release of the shorter version.
    if extended_is_prerelease:
        # new < current only if the *current* side is the pre-release.
        return not longer_is_current
    # new < current only if the *current* side carries the extra segments.
    return longer_is_current


def git_ro(repo: Path, *args: str) -> str:
    """Run a read-only git command against the updater's (untrusted) repo.

    Same hardening as create_pr.py: disable code-executing git knobs and
    never push from this checkout.
    """
    result = subprocess.run(
        [
            "git",
            "-C",
            str(repo),
            "-c",
            "core.fsmonitor=false",
            "-c",
            "core.hooksPath=/dev/null",
            *args,
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


def allowed_roots(
    repo: Path,
    name: str,
    *,
    base_ref: str = "origin/main",
) -> tuple[str, ...]:
    """Return the paths a package update is allowed to touch."""
    # Read companions from the base branch, not the tree the updater edited.
    try:
        companions = git_ro(
            repo, "show", f"{base_ref}:packages/{name}/update-companions"
        )
    except subprocess.CalledProcessError:
        companions = ""
    names = [name] + [
        stripped
        for line in companions.splitlines()
        if (stripped := line.strip()) and not stripped.startswith("#")
    ]
    return tuple(f"packages/{companion}/" for companion in names)


def changed_paths(repo: Path, *, base_ref: str = "origin/main") -> list[str]:
    """List every work-tree path that differs from the base branch."""
    tracked = git_ro(repo, "diff", "--name-only", "-z", base_ref)
    untracked = git_ro(repo, "ls-files", "--others", "--exclude-standard", "-z")
    return sorted({p for p in (tracked + untracked).split("\0") if p})


def check_confinement(
    repo: Path,
    allowed: tuple[str, ...],
    name: str,
    *,
    base_ref: str = "origin/main",
) -> None:
    """Abort if the (untrusted) updater changed files outside its territory."""
    stray = [
        p for p in changed_paths(repo, base_ref=base_ref) if not p.startswith(allowed)
    ]
    if stray:
        log.error(
            "update of %s changed files outside %s: %s",
            name,
            ", ".join(allowed),
            ", ".join(stray),
        )
        sys.exit(1)


def sync_path(src: Path, dst: Path) -> None:
    """Mirror one allowed file or directory from the dirty tree."""
    if dst.is_symlink() or dst.is_file():
        dst.unlink()
    elif dst.is_dir():
        shutil.rmtree(dst)
    if src.is_dir() and not src.is_symlink():
        shutil.copytree(src, dst, symlinks=True)
    elif src.is_symlink() or src.exists():
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst, follow_symlinks=False)


@dataclass(frozen=True)
class MrConfig:
    """All the data needed to publish an update branch and its MR."""

    branch: str
    title: str
    body: str
    commit_message: str


def build_config(
    *,
    name: str,
    current_version: str,
    new_version: str,
    changelog_url: str,
) -> MrConfig:
    """Build branch, title, body, and commit message for a package update."""
    branch = f"update/{name}"
    title = f"{name}: {current_version} -> {new_version}"
    body = (
        f"Automated update of {name} from {current_version} to {new_version}.\n\n"
        "This MR was created by the fork maintenance pipeline. It will be "
        "merged automatically once its validation pipeline succeeds and its "
        "head commit is unchanged."
    )
    commit_message = f"{title}\n\n{changelog_url}" if changelog_url else title
    return MrConfig(
        branch=branch, title=title, body=body, commit_message=commit_message
    )


def clone_and_publish(
    config: MrConfig,
    allowed: tuple[str, ...],
    *,
    remote_url: str,
    git_env: dict[str, str],
    default_branch: str,
    bot_name: str,
    bot_email: str,
) -> Path:
    """Build the update branch in a pristine clone and push it.

    The updater had write access to the work tree and its .git, so that
    checkout must never see the token: shallow-clone the base branch
    afresh and copy over only the confined paths.
    """
    dirty = Path.cwd()
    clean = Path(os.environ.get("CI_TEMP_DIR") or tempfile.gettempdir()) / "clean-repo"
    if clean.exists():
        shutil.rmtree(clean)

    def git(*args: str, check: bool = True) -> int:
        return subprocess.run(
            ["git", "-C", str(clean), *args], env=git_env, check=check
        ).returncode

    subprocess.run(
        [
            "git",
            "clone",
            "--quiet",
            "--depth=1",
            "--branch",
            default_branch,
            remote_url,
            str(clean),
        ],
        check=True,
        env=git_env,
    )
    git("config", "user.name", bot_name)
    git("config", "user.email", bot_email)
    git("checkout", "-q", "-B", config.branch)

    for rel in allowed:
        sync_path(dirty / rel, clean / rel)

    git("add", "--all", "--", *allowed)
    if git("diff", "--quiet", "--cached", check=False) != 0:
        git("commit", "-q", "-m", config.commit_message, "--signoff")
    git("push", "--force", remote_url, f"HEAD:{config.branch}")
    return clean


def find_open_mr(api: GitLabApi, project: str, branch: str) -> dict | None:
    """Return the open MR for a source branch, or None."""
    mrs = list(
        api.paginate(
            f"/projects/{project}/merge_requests",
            params={"state": "opened", "source_branch": branch},
        )
    )
    return mrs[0] if mrs else None


def create_or_update_mr(
    api: GitLabApi,
    project: str,
    config: MrConfig,
    *,
    default_branch: str,
    labels: str,
) -> str:
    """Create or update the MR for the update branch; return the action."""
    existing = find_open_mr(api, project, config.branch)
    if existing:
        iid = existing["iid"]
        log.info("Updating existing MR !%s (%s)", iid, config.branch)
        api.request(
            "PUT",
            f"/projects/{project}/merge_requests/{iid}",
            json_body={"title": config.title, "description": config.body},
        )
        return "updated"

    log.info("Creating MR for %s", config.branch)
    api.request(
        "POST",
        f"/projects/{project}/merge_requests",
        json_body={
            "source_branch": config.branch,
            "target_branch": default_branch,
            "title": config.title,
            "description": config.body,
            "labels": labels,
            "remove_source_branch": True,
        },
    )
    return "created"


def publish_package_update(
    *,
    name: str,
    current_version: str,
    new_version: str,
    changelog_url: str,
) -> str:
    """Confinement-check, publish the branch, and open/update its MR."""
    config = build_config(
        name=name,
        current_version=current_version,
        new_version=new_version,
        changelog_url=changelog_url,
    )
    allowed = allowed_roots(Path.cwd(), name)
    check_confinement(Path.cwd(), allowed, name)

    gitlab = resolve_config()
    bot_name = os.environ.get("CI_BOT_NAME", BOT_NAME)
    bot_email = os.environ.get(
        "CI_BOT_EMAIL", f"{bot_name}@users.noreply.{_host(gitlab.base_url)}"
    )
    clone_and_publish(
        config,
        allowed,
        remote_url=gitlab.http_remote_url(),
        git_env=gitlab.git_env(),
        default_branch=os.environ.get("DEFAULT_BRANCH", "main"),
        bot_name=bot_name,
        bot_email=bot_email,
    )
    return create_or_update_mr(
        gitlab.api(),
        gitlab.project_url_encoded,
        config,
        default_branch=os.environ.get("DEFAULT_BRANCH", "main"),
        labels=os.environ.get("MR_LABELS", "dependencies,automated"),
    )


def _host(base_url: str) -> str:
    """Extract the host portion of a base URL for noreply emails."""
    return urlparse(base_url).netloc
