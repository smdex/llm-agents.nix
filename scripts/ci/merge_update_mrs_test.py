"""Tests for the guarded merger: eligibility, validation, SHA guard.

Negative eligibility is the security boundary: an MR that fails any
eligibility rule must never reach the merge call.
"""

from __future__ import annotations

import unittest
from typing import TYPE_CHECKING, Any

if TYPE_CHECKING:
    from collections.abc import Iterator

from ci.gitlab_api import GitLabApiError
from ci.merge_update_mrs import (
    Validation,
    eligible,
    merge_candidate,
    validation_state,
)

BOT = "llm-agents-bot"


def mr(**overrides: Any) -> dict[str, Any]:
    base = {
        "iid": 7,
        "title": "paseo: 0.11.0 -> 0.11.2",
        "state": "opened",
        "source_branch": "update/paseo",
        "source_project_id": 1,
        "target_project_id": 1,
        "target_branch": "main",
        "sha": "a" * 40,
        "author": {"username": BOT},
        "labels": ["dependencies", "automated"],
        "draft": False,
        "work_in_progress": False,
        "head_pipeline": None,
    }
    base.update(overrides)
    return base


class EligibilityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.kwargs = {"bot_username": BOT, "default_branch": "main"}

    def test_bot_update_mr_is_eligible(self) -> None:
        ok, _reason = eligible(mr(), **self.kwargs)
        self.assertTrue(ok)

    def test_human_author_is_rejected(self) -> None:
        ok, reason = eligible(mr(author={"username": "alice"}), **self.kwargs)
        self.assertFalse(ok)
        self.assertIn("not the bot", reason)

    def test_non_update_branch_is_rejected(self) -> None:
        ok, reason = eligible(mr(source_branch="feature/x"), **self.kwargs)
        self.assertFalse(ok)
        self.assertIn("update/", reason)

    def test_cross_project_source_is_rejected(self) -> None:
        ok, _reason = eligible(mr(source_project_id=2), **self.kwargs)
        self.assertFalse(ok)

    def test_malformed_update_branch_is_rejected(self) -> None:
        ok, _reason = eligible(mr(source_branch="update/foo/bar"), **self.kwargs)
        self.assertFalse(ok)

    def test_wrong_target_branch_is_rejected(self) -> None:
        ok, reason = eligible(mr(target_branch="trunk"), **self.kwargs)
        self.assertFalse(ok)
        self.assertIn("default", reason)

    def test_missing_automated_label_is_rejected(self) -> None:
        ok, reason = eligible(mr(labels=["dependencies"]), **self.kwargs)
        self.assertFalse(ok)
        self.assertIn("label", reason)

    def test_draft_is_rejected(self) -> None:
        ok, reason = eligible(mr(draft=True), **self.kwargs)
        self.assertFalse(ok)
        self.assertIn("draft", reason)

    def test_wip_is_rejected(self) -> None:
        ok, reason = eligible(mr(work_in_progress=True), **self.kwargs)
        self.assertFalse(ok)
        self.assertIn("draft", reason)


class FakeApi:
    """Replays canned responses for merge_candidate/validation_state."""

    def __init__(
        self,
        *,
        fresh_mr: dict[str, Any] | None = None,
        statuses: list[dict[str, Any]] | None = None,
        merge_error: GitLabApiError | None = None,
    ) -> None:
        self.fresh_mr = fresh_mr
        self.statuses = statuses or []
        self.merge_error = merge_error
        self.calls: list[dict[str, Any]] = []

    def paginate(self, _path: str) -> Iterator[dict[str, Any]]:
        return iter(self.statuses)

    def request(self, method: str, path: str, *, json_body: Any = None) -> Any:
        self.calls.append({"kind": method, "path": path, "json_body": json_body})
        if method == "PUT" and path.endswith("/merge"):
            if self.merge_error:
                raise self.merge_error
            return {"state": "merged"}
        if method == "GET" and "/statuses" in path:
            return self.statuses
        if method == "GET":
            return self.fresh_mr
        message = f"unexpected {method} {path}"
        raise AssertionError(message)


class ValidationStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.api = FakeApi(statuses=[])

    def test_gitlab_pipeline_success_is_ready(self) -> None:
        state, _detail = validation_state(
            mr(
                head_pipeline={
                    "status": "success",
                    "sha": "a" * 40,
                    "source": "merge_request_event",
                }
            ),
            api=self.api,
            project="1",
        )
        self.assertIs(state, Validation.READY)

    def test_external_pipeline_success_is_not_mr_validation(self) -> None:
        state, _detail = validation_state(
            mr(
                head_pipeline={
                    "status": "success",
                    "sha": "a" * 40,
                    "source": "external",
                }
            ),
            api=self.api,
            project="1",
        )
        self.assertIs(state, Validation.PENDING)

    def test_gitlab_pipeline_running_is_pending(self) -> None:
        state, detail = validation_state(
            mr(head_pipeline={"status": "running", "sha": "a" * 40}),
            api=self.api,
            project="1",
        )
        self.assertIs(state, Validation.PENDING)
        self.assertIn("running", detail)

    def test_gitlab_pipeline_failed_is_failed(self) -> None:
        state, _detail = validation_state(
            mr(head_pipeline={"status": "failed", "sha": "a" * 40}),
            api=self.api,
            project="1",
        )
        self.assertIs(state, Validation.FAILED)

    def test_stale_pipeline_sha_is_not_evidence(self) -> None:
        state, _detail = validation_state(
            mr(head_pipeline={"status": "success", "sha": "b" * 40}),
            api=self.api,
            project="1",
        )
        self.assertIs(state, Validation.PENDING)

    def test_woodpecker_success_is_ready(self) -> None:
        api = FakeApi(
            statuses=[{"name": "ci/woodpecker/pr/validate-mr", "status": "success"}]
        )
        state, _detail = validation_state(mr(), api=api, project="1")
        self.assertIs(state, Validation.READY)

    def test_woodpecker_running_is_pending(self) -> None:
        api = FakeApi(
            statuses=[{"name": "ci/woodpecker/pr/validate-mr", "status": "running"}]
        )
        state, _detail = validation_state(mr(), api=api, project="1")
        self.assertIs(state, Validation.PENDING)

    def test_woodpecker_failed_is_failed(self) -> None:
        api = FakeApi(
            statuses=[{"name": "ci/woodpecker/pr/validate-mr", "status": "failed"}]
        )
        state, detail = validation_state(mr(), api=api, project="1")
        self.assertIs(state, Validation.FAILED)
        self.assertIn("failed", detail)

    def test_mixed_woodpecker_statuses_fail_closed(self) -> None:
        api = FakeApi(
            statuses=[
                {"name": "ci/woodpecker/pr/validate-mr", "status": "success"},
                {"name": "ci/woodpecker/pipeline/other", "status": "failed"},
            ]
        )
        state, _detail = validation_state(mr(), api=api, project="1")
        self.assertIs(state, Validation.FAILED)

    def test_unrelated_success_is_not_validation_evidence(self) -> None:
        api = FakeApi(
            statuses=[{"name": "ci/woodpecker/cron/maintenance", "status": "success"}]
        )
        state, _detail = validation_state(mr(), api=api, project="1")
        self.assertIs(state, Validation.PENDING)

    def test_no_evidence_is_pending_never_ready(self) -> None:
        state, detail = validation_state(mr(), api=self.api, project="1")
        self.assertIs(state, Validation.PENDING)
        self.assertIn("no validation", detail)


class MergeCandidateTest(unittest.TestCase):
    def mergeable_mr(self) -> dict[str, Any]:
        return mr(
            detailed_merge_status="mergeable",
            merge_status="can_be_merged",
            head_pipeline={
                "status": "success",
                "sha": "a" * 40,
                "source": "merge_request_event",
            },
        )

    def test_merges_with_pinned_sha(self) -> None:
        api = FakeApi(fresh_mr=self.mergeable_mr())
        done, _reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertTrue(done)
        merge_call = api.calls[-1]
        self.assertTrue(merge_call["path"].endswith("/merge_requests/7/merge"))
        self.assertEqual(merge_call["json_body"]["sha"], "a" * 40)
        self.assertTrue(merge_call["json_body"]["squash"])
        self.assertTrue(merge_call["json_body"]["remove_source_branch"])

    def test_head_sha_guard_blocks_moved_mr(self) -> None:
        api = FakeApi(fresh_mr=self.mergeable_mr() | {"sha": "b" * 40})
        done, reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertFalse(done)
        self.assertIn("moved", reason)
        self.assertFalse(any(call["kind"] == "PUT" for call in api.calls))

    def test_closed_mr_is_not_merged(self) -> None:
        api = FakeApi(fresh_mr=self.mergeable_mr() | {"state": "merged"})
        done, _reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertFalse(done)

    def test_unmergeable_mr_is_not_merged(self) -> None:
        api = FakeApi(fresh_mr=mr(detailed_merge_status="discussions_not_resolved"))
        done, _reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertFalse(done)
        self.assertFalse(any(call["kind"] == "PUT" for call in api.calls))

    def test_changed_target_is_rejected_on_fresh_read(self) -> None:
        api = FakeApi(fresh_mr=self.mergeable_mr() | {"target_branch": "other"})
        done, _reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertFalse(done)
        self.assertFalse(any(call["kind"] == "PUT" for call in api.calls))

    def test_restarted_validation_prevents_merge(self) -> None:
        api = FakeApi(
            fresh_mr=self.mergeable_mr()
            | {"head_pipeline": {"status": "running", "sha": "a" * 40}}
        )
        done, _reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertFalse(done)
        self.assertFalse(any(call["kind"] == "PUT" for call in api.calls))

    def test_blocking_detailed_status_overrides_legacy_mergeable(self) -> None:
        api = FakeApi(
            fresh_mr=self.mergeable_mr()
            | {"detailed_merge_status": "discussions_not_resolved"}
        )
        done, _reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertFalse(done)

    def test_refusal_status_does_not_raise(self) -> None:
        api = FakeApi(
            fresh_mr=self.mergeable_mr(),
            merge_error=GitLabApiError("PUT", "/merge", 405, "method not allowed"),
        )
        done, reason = merge_candidate(
            7,
            api=api,
            project="1",
            observed_sha="a" * 40,
            bot=BOT,
            default_branch="main",
        )
        self.assertFalse(done)
        self.assertIn("405", reason)

    def test_server_error_raises(self) -> None:
        api = FakeApi(
            fresh_mr=self.mergeable_mr(),
            merge_error=GitLabApiError("PUT", "/merge", 502, "bad gateway"),
        )
        with self.assertRaises(GitLabApiError):
            merge_candidate(
                7,
                api=api,
                project="1",
                observed_sha="a" * 40,
                bot=BOT,
                default_branch="main",
            )


if __name__ == "__main__":
    unittest.main()
