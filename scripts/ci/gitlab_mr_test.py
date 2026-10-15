"""Tests for MR publishing: downgrade guard and path confinement."""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import Any

from ci.gitlab_api import GitLabApiError
from ci.gitlab_mr import (
    allowed_roots,
    build_config,
    changed_paths,
    check_confinement,
    create_or_update_mr,
    is_downgrade,
)


class FakeApi:
    """Records API calls; merge_requests are preloaded per test."""

    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []
        self.open_mrs: list[dict[str, Any]] = []

    def paginate(self, _path: str, *, params: dict[str, str]) -> list[dict[str, Any]]:
        self.calls.append({"kind": "list", "params": params})
        source = params.get("source_branch", "")
        return [mr for mr in self.open_mrs if mr["source_branch"] == source]

    def request(self, method: str, path: str, *, json_body: Any = None) -> Any:
        self.calls.append({"kind": method, "path": path, "json_body": json_body})
        return {"iid": 1}


class IsDowngradeTest(unittest.TestCase):
    def test_equal_versions(self) -> None:
        self.assertFalse(is_downgrade("1.2.3", "1.2.3"))

    def test_numeric_segments(self) -> None:
        self.assertFalse(is_downgrade("1.2.3", "1.2.4"))
        self.assertTrue(is_downgrade("1.2.4", "1.2.3"))
        self.assertTrue(is_downgrade("2.0", "1.9.9"))
        self.assertFalse(is_downgrade("1.9.9", "2.0"))

    def test_segment_count(self) -> None:
        self.assertFalse(is_downgrade("1.2", "1.2.1"))
        self.assertTrue(is_downgrade("1.2.1", "1.2"))

    def test_prerelease_orders_below_release(self) -> None:
        self.assertTrue(is_downgrade("1.2.0", "1.2.0-rc.1"))
        self.assertFalse(is_downgrade("1.2.0-rc.1", "1.2.0"))
        self.assertTrue(is_downgrade("1.2.0", "1.2.0-beta.2"))

    def test_fork_suffixes(self) -> None:
        self.assertFalse(is_downgrade("0.11.0-beta.2", "0.11.2-smdex"))
        self.assertFalse(is_downgrade("0.10.0-smdex", "0.11.0-smdex"))
        self.assertTrue(is_downgrade("0.11.2-smdex", "0.10.0-smdex"))


class BuildConfigTest(unittest.TestCase):
    def test_package_update_shape(self) -> None:
        config = build_config(
            name="paseo",
            current_version="0.11.0",
            new_version="0.11.2",
            changelog_url="https://example.com/changelog",
        )
        self.assertEqual(config.branch, "update/paseo")
        self.assertEqual(config.title, "paseo: 0.11.0 -> 0.11.2")
        self.assertIn("changelog", config.commit_message)


class RepoFixture:
    """A git repository with a base branch and a dirty work tree."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.run(["git", "init", "-q", "-b", "main"])
        self.run(["git", "config", "user.email", "test@example.com"])
        self.run(["git", "config", "user.name", "Test"])
        (path / "packages" / "foo").mkdir(parents=True)
        (path / "packages" / "foo" / "package.nix").write_text("old\n")
        (path / "packages" / "foo" / "update-companions").write_text(
            "# companions\nbar\n"
        )
        self.run(["git", "add", "-A"])
        self.run(["git", "commit", "-q", "-m", "base"])

    def run(self, cmd: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            cmd, cwd=self.path, check=True, capture_output=True, text=True
        )


class ConfinementTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        self.repo = RepoFixture(Path(self._temp.name))
        # The driver's work tree is a branch off main with origin refs.
        self.repo.run(["git", "config", "remote.origin.url", "."])
        self.repo.run(
            [
                "git",
                "config",
                "remote.origin.fetch",
                "+refs/heads/*:refs/remotes/origin/*",
            ]
        )
        self.repo.run(["git", "fetch", "-q", "origin"])
        self.repo.run(["git", "checkout", "-q", "-B", "update/foo"])

    def test_companions_extend_allowed_roots(self) -> None:
        allowed = allowed_roots(self.repo.path, "foo")
        self.assertEqual(allowed, ("packages/foo/", "packages/bar/"))

    def test_missing_companions_file_yields_only_package(self) -> None:
        allowed = allowed_roots(self.repo.path, "nonexistent")
        self.assertEqual(allowed, ("packages/nonexistent/",))

    def test_changes_inside_package_are_listed(self) -> None:
        (self.repo.path / "packages" / "foo" / "package.nix").write_text("new\n")
        self.assertEqual(
            changed_paths(self.repo.path),
            ["packages/foo/package.nix"],
        )

    def test_confined_change_passes(self) -> None:
        (self.repo.path / "packages" / "foo" / "package.nix").write_text("new\n")
        check_confinement(self.repo.path, ("packages/foo/",), "foo")  # must not raise

    def test_stray_change_aborts(self) -> None:
        (self.repo.path / "evil.sh").write_text("rm -rf /\n")
        with self.assertRaises(SystemExit) as ctx:
            check_confinement(self.repo.path, ("packages/foo/",), "foo")
        self.assertEqual(ctx.exception.code, 1)

    def test_modified_shared_file_outside_package_aborts(self) -> None:
        shared = self.repo.path / "packages" / "shared"
        shared.mkdir(parents=True)
        (shared / "package.nix").write_text("x\n")
        with self.assertRaises(SystemExit):
            check_confinement(self.repo.path, ("packages/foo/",), "foo")


class CreateOrUpdateMrTest(unittest.TestCase):
    def test_creates_mr_with_expected_fields(self) -> None:
        api = FakeApi()
        config = build_config(
            name="foo", current_version="1", new_version="2", changelog_url=""
        )
        action = create_or_update_mr(
            api, "1", config, default_branch="main", labels="dependencies,automated"
        )
        body = api.calls[-1]["json_body"]
        self.assertEqual(action, "created")
        self.assertEqual(body["source_branch"], "update/foo")
        self.assertEqual(body["target_branch"], "main")
        self.assertEqual(body["labels"], "dependencies,automated")
        self.assertTrue(body["remove_source_branch"])

    def test_updates_existing_mr(self) -> None:
        api = FakeApi()
        api.open_mrs = [{"iid": 42, "source_branch": "update/foo"}]
        config = build_config(
            name="foo", current_version="1", new_version="2", changelog_url=""
        )
        action = create_or_update_mr(
            api, "1", config, default_branch="main", labels="dependencies,automated"
        )
        self.assertEqual(action, "updated")
        self.assertTrue(api.calls[-1]["path"].endswith("/merge_requests/42"))
        self.assertEqual(api.calls[-1]["kind"], "PUT")

    def test_api_error_propagates(self) -> None:
        class RaisingApi(FakeApi):
            def request(
                self,
                method: str,
                path: str,
                *,
                json_body: Any = None,  # noqa: ARG002 — unused in this stub
            ) -> Any:
                raise GitLabApiError(method, path, 500, "boom")

        with self.assertRaises(GitLabApiError):
            create_or_update_mr(
                RaisingApi(),
                "1",
                build_config(
                    name="foo", current_version="1", new_version="2", changelog_url=""
                ),
                default_branch="main",
                labels="automated",
            )


if __name__ == "__main__":
    unittest.main()
