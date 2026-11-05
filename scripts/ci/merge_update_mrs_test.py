"""Tests for the guarded merger: eligibility, validation, SHA guard.

Negative eligibility is the security boundary: an MR that fails any
eligibility rule must never reach the merge call.
"""

from __future__ import annotations

import unittest
from typing import TYPE_CHECKING, Any
from unittest.mock import patch

if TYPE_CHECKING:
    from collections.abc import Iterator

from ci import merge_update_mrs
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

    def test_non_main_source_must_match_target(self) -> None:
        kwargs = {"bot_username": BOT, "default_branch": "chiki"}
        self.assertTrue(
            eligible(
                mr(source_branch="update-branch/chiki/paseo", target_branch="chiki"),
                **kwargs,
            )[0]
        )
        for source in (
            "update/paseo",
            "update-branch/main/paseo",
            "update-branch/chiki/foo/bar",
        ):
            self.assertFalse(
                eligible(mr(source_branch=source, target_branch="chiki"), **kwargs)[0]
            )
        self.assertFalse(
            eligible(mr(source_branch="update-branch/chiki/paseo"), **self.kwargs)[0]
        )

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
        pipelines: list[dict[str, Any]] | None = None,
        merge_error: GitLabApiError | None = None,
        changes: dict[str, Any] | None = None,
    ) -> None:
        self.changes = (
            changes
            if changes is not None
            else {
                "overflow": False,
                "diff_refs": {"head_sha": "a" * 40},
                "changes": [
                    {
                        "old_path": "packages/paseo/package.nix",
                        "new_path": "packages/paseo/package.nix",
                    }
                ],
            }
        )
        self.fresh_mr = fresh_mr
        self.statuses = statuses
        head = (fresh_mr or {}).get("head_pipeline") or {}
        self.pipelines = (
            pipelines
            if pipelines is not None
            else ([head | {"id": 1}] if head.get("source") else [])
        )
        self.merge_error = merge_error
        self.calls: list[dict[str, Any]] = []

    def paginate(self, path: str) -> Iterator[dict[str, Any]]:
        self.calls.append({"kind": "paginate", "path": path})
        if path.endswith("/pipelines"):
            return iter(self.pipelines)
        if path.endswith("/jobs"):
            if self.statuses is not None:
                return iter(self.statuses)
            pipeline_id = int(path.split("/")[-2])
            pipeline = next(p for p in self.pipelines if p["id"] == pipeline_id)
            return iter(
                [
                    {
                        "id": 1,
                        "name": "validate-update-mr",
                        "stage": "validate",
                        "status": pipeline.get("status"),
                        "runner": {"id": 1},
                    }
                ]
            )
        return iter(self.statuses or [])

    def request(self, method: str, path: str, *, json_body: Any = None) -> Any:
        self.calls.append({"kind": method, "path": path, "json_body": json_body})
        if method == "PUT" and path.endswith("/merge"):
            if self.merge_error:
                raise self.merge_error
            return {"state": "merged"}
        if method == "GET" and path.endswith("/changes"):
            return self.changes
        if method == "GET" and "/statuses" in path:
            return self.statuses
        if method == "GET":
            return self.fresh_mr
        message = f"unexpected {method} {path}"
        raise AssertionError(message)


class ValidationStateTest(unittest.TestCase):
    def test_validation_job_not_aggregate_pipeline_status(self) -> None:
        pipeline = {
            "id": 3,
            "sha": "a" * 40,
            "source": "merge_request_event",
            "status": "failed",
        }
        job = {
            "id": 10,
            "name": "validate-update-mr",
            "stage": "validate",
            "status": "success",
            "runner": {"id": 1},
        }
        api = FakeApi(pipelines=[pipeline], statuses=[job])
        state, _ = validation_state(mr(), api=api, project="1")
        self.assertIs(state, Validation.READY)
        self.assertEqual(api.calls[1]["path"], "/projects/1/pipelines/3/jobs")

    def test_latest_real_pipeline_for_exact_sha(self) -> None:
        for status, expected in (
            ("success", Validation.READY),
            ("running", Validation.PENDING),
            ("failed", Validation.FAILED),
        ):
            with self.subTest(status=status):
                api = FakeApi(
                    pipelines=[
                        {
                            "id": 5,
                            "sha": "a" * 40,
                            "source": "external",
                            "status": "failed",
                        },
                        {
                            "id": 3,
                            "sha": "a" * 40,
                            "source": "merge_request_event",
                            "status": status,
                        },
                        {
                            "id": 2,
                            "sha": "a" * 40,
                            "source": "merge_request_event",
                            "status": "success",
                        },
                        {
                            "id": 4,
                            "sha": "b" * 40,
                            "source": "merge_request_event",
                            "status": "success",
                        },
                    ]
                )
                state, _ = validation_state(
                    mr(
                        head_pipeline={
                            "status": "failed",
                            "source": "external",
                            "sha": "a" * 40,
                        }
                    ),
                    api=api,
                    project="1",
                )
                self.assertIs(state, expected)
                self.assertEqual(
                    api.calls[0]["path"], "/projects/1/merge_requests/7/pipelines"
                )

    def test_validation_job_evidence(self) -> None:
        pipeline = {
            "id": 3,
            "sha": "a" * 40,
            "source": "merge_request_event",
            "status": "success",
        }
        job = {
            "id": 10,
            "name": "validate-update-mr",
            "stage": "validate",
            "runner": {"id": 1},
        }
        for jobs, expected in (
            ([], Validation.PENDING),
            ([job | {"status": "running"}], Validation.PENDING),
            ([job | {"status": "failed"}], Validation.FAILED),
            ([job | {"status": "skipped"}], Validation.FAILED),
            ([job | {"status": "success", "runner": None}], Validation.PENDING),
            ([job | {"status": "success", "stage": "external"}], Validation.PENDING),
            (
                [job | {"status": "success"}, job | {"id": 11, "status": "running"}],
                Validation.PENDING,
            ),
            (
                [job | {"status": "success"}, job | {"id": 11, "status": "failed"}],
                Validation.FAILED,
            ),
        ):
            with self.subTest(jobs=jobs):
                state, _ = validation_state(
                    mr(), api=FakeApi(pipelines=[pipeline], statuses=jobs), project="1"
                )
                self.assertIs(state, expected)

    def test_missing_or_external_evidence_is_pending(self) -> None:
        for pipelines in (
            [],
            [{"id": 1, "sha": "a" * 40, "source": "external", "status": "failed"}],
        ):
            with self.subTest(pipelines=pipelines):
                state, _ = validation_state(
                    mr(), api=FakeApi(pipelines=pipelines), project="1"
                )
                self.assertIs(state, Validation.PENDING)

    def test_missing_sha_is_pending(self) -> None:
        state, _ = validation_state(mr(sha=""), api=FakeApi(), project="1")
        self.assertIs(state, Validation.PENDING)

    def test_source_is_fetched_when_missing(self) -> None:
        class Api(FakeApi):
            def request(self, method: str, path: str, *, json_body: Any = None) -> Any:
                self.calls.append({"kind": method, "path": path, "body": json_body})
                return {"source": "merge_request_event"}

        api = Api(pipelines=[{"id": 3, "sha": "a" * 40, "status": "success"}])
        state, _ = validation_state(mr(), api=api, project="1")
        self.assertIs(state, Validation.READY)
        self.assertEqual(api.calls[1]["path"], "/projects/1/pipelines/3")


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

    def test_changes_guard(self) -> None:
        for old, new, allowed in (
            ("packages/paseo/package.nix", "packages/paseo/package.nix", True),
            ("packages/companion/update.py", "packages/companion/update.py", True),
            (".gitlab-ci.yml", ".gitlab-ci.yml", False),
            ("scripts/ci/validate-mr.sh", "scripts/ci/validate-mr.sh", False),
            (".github/ci/check_maintainers.py", "packages/paseo/file", False),
            ("packages/paseo/file", "packages/formatter/treefmt.nix", False),
        ):
            with self.subTest(old=old, new=new):
                api = FakeApi(
                    fresh_mr=self.mergeable_mr(),
                    changes={
                        "overflow": False,
                        "diff_refs": {"head_sha": "a" * 40},
                        "changes": [{"old_path": old, "new_path": new}],
                    },
                )
                done, _ = merge_candidate(
                    7,
                    api=api,
                    project="1",
                    observed_sha="a" * 40,
                    bot=BOT,
                    default_branch="main",
                )
                self.assertEqual(done, allowed)
                self.assertEqual(any(c["kind"] == "PUT" for c in api.calls), allowed)

    def test_incomplete_or_stale_changes_refused(self) -> None:
        for changes in (
            {},
            {"overflow": True},
            {"overflow": False, "diff_refs": {"head_sha": "b" * 40}, "changes": [{}]},
        ):
            with self.subTest(changes=changes):
                api = FakeApi(fresh_mr=self.mergeable_mr(), changes=changes)
                done, _ = merge_candidate(
                    7,
                    api=api,
                    project="1",
                    observed_sha="a" * 40,
                    bot=BOT,
                    default_branch="main",
                )
                self.assertFalse(done)
                self.assertFalse(any(c["kind"] == "PUT" for c in api.calls))

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


class MainExitTest(unittest.TestCase):
    def run_main(
        self, mrs: list[dict[str, Any]], *, env: dict[str, str] | None = None
    ) -> None:
        class Api(FakeApi):
            def paginate(self, path: str, **_kwargs: Any) -> Iterator[dict[str, Any]]:
                if path.endswith("/merge_requests"):
                    return iter(mrs)
                if path.endswith("/pipelines"):
                    item = next(
                        item for item in mrs if f"/{item['iid']}/pipelines" in path
                    )
                    head = item.get("head_pipeline") or {}
                    return iter(
                        [head | {"id": item["iid"]}] if head.get("source") else []
                    )
                if path.endswith("/jobs"):
                    item = next(
                        item for item in mrs if f"/pipelines/{item['iid']}/jobs" in path
                    )
                    head = item.get("head_pipeline") or {}
                    return iter(
                        [
                            {
                                "id": 1,
                                "name": "validate-update-mr",
                                "stage": "validate",
                                "status": head.get("status"),
                                "runner": {"id": 1},
                            }
                        ]
                    )
                return iter(self.statuses or [])

            def request(self, method: str, path: str, *, json_body: Any = None) -> Any:
                if method == "GET" and path.endswith("/changes"):
                    return self.changes
                if method == "GET" and "/merge_requests/" in path:
                    return next(
                        item for item in mrs if path.endswith(f"/{item['iid']}")
                    )
                return super().request(method, path, json_body=json_body)

        api = Api()
        with (
            patch.object(merge_update_mrs, "resolve_config") as config,
            patch.object(
                merge_update_mrs, "resolve_default_branch", return_value="main"
            ),
            patch.object(merge_update_mrs, "bot_username", return_value=BOT),
            patch.dict(
                "os.environ",
                env if env is not None else {"MERGE_WAIT_TIMEOUT": "0"},
                clear=True,
            ),
            patch("sys.argv", ["merge_update_mrs.py"]),
        ):
            config.return_value.api.return_value = api
            config.return_value.project_url_encoded = "1"
            merge_update_mrs.main()

    def test_failed_eligible_validation_exits_nonzero(self) -> None:
        with self.assertRaises(SystemExit) as exit_code:
            self.run_main(
                [
                    mr(
                        head_pipeline={
                            "status": "failed",
                            "sha": "a" * 40,
                            "source": "merge_request_event",
                        }
                    )
                ]
            )
        self.assertEqual(exit_code.exception.code, 3)

    def test_pending_eligible_validation_times_out_nonzero(self) -> None:
        with self.assertRaises(SystemExit) as exit_code:
            self.run_main([mr()])
        self.assertEqual(exit_code.exception.code, 3)

    def test_gitlab_pending_does_not_wait_for_occupied_runner(self) -> None:
        with (
            patch.object(merge_update_mrs.time, "sleep") as sleep,
            self.assertRaises(SystemExit),
        ):
            self.run_main([mr()], env={"GITLAB_CI": "true"})
        sleep.assert_not_called()

    def test_failed_ineligible_mr_does_not_fail(self) -> None:
        self.run_main(
            [mr(author={"username": "alice"}, head_pipeline={"status": "failed"})]
        )

    def test_successful_merge_does_not_fail(self) -> None:
        self.run_main([MergeCandidateTest().mergeable_mr()])

    def test_failed_and_successful_mrs_exit_partial(self) -> None:
        successful = MergeCandidateTest().mergeable_mr()
        failed = mr(
            iid=8, head_pipeline=successful["head_pipeline"] | {"status": "failed"}
        )
        with (
            self.assertLogs(merge_update_mrs.log, level="INFO") as logs,
            self.assertRaises(SystemExit) as exit_code,
        ):
            self.run_main([failed, successful])
        self.assertEqual(exit_code.exception.code, 3)
        self.assertTrue(any("1 merged, 1 refused" in line for line in logs.output))

    def test_unhandled_error_propagates(self) -> None:
        with (
            patch.object(
                merge_update_mrs, "sweep_once", side_effect=RuntimeError("boom")
            ),
            self.assertRaisesRegex(RuntimeError, "boom"),
        ):
            self.run_main([])


if __name__ == "__main__":
    unittest.main()
