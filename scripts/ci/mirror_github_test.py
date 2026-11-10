"""Tests for the GitLab to GitHub mirror."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from scripts.ci import mirror_github
from scripts.ci.mirror_github import mirror


class MirrorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.work = self.root / "work"
        self.gitlab = self.root / "gitlab.git"
        self.github = self.root / "github.git"
        for repo in (self.gitlab, self.github):
            subprocess.run(["git", "init", "--bare", "--quiet", str(repo)], check=True)
        subprocess.run(["git", "init", "--quiet", str(self.work)], check=True)
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        self.git("checkout", "-b", "main")
        self.commit("initial")
        self.git("branch", "chiki")
        for remote in (self.gitlab, self.github):
            self.git("push", str(remote), "main", "chiki")
        self.git(
            "push",
            str(self.gitlab),
            "main:maintenance/github-main",
            "chiki:maintenance/github-chiki",
        )

    def git(self, *args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(self.work), *args],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.strip()

    def commit(self, message: str) -> str:
        self.git("commit", "--allow-empty", "-m", message)
        return self.git("rev-parse", "HEAD")

    def tip(self, repo: Path, branch: str) -> str:
        return subprocess.check_output(
            ["git", "--git-dir", str(repo), "rev-parse", f"refs/heads/{branch}"],
            text=True,
        ).strip()

    def run_mirror(self) -> None:
        mirror(str(self.gitlab), str(self.github), os.environ.copy())

    def test_normal_and_rewrite(self) -> None:
        self.git("checkout", "main")
        main = self.commit("next")
        self.git("checkout", "chiki")
        self.git("merge", "--ff-only", "main")
        chiki = self.commit("fork")
        self.git("push", str(self.gitlab), "main", "chiki")
        self.run_mirror()
        self.assertEqual(self.tip(self.github, "main"), main)
        self.assertEqual(self.tip(self.github, "chiki"), chiki)
        self.assertEqual(self.tip(self.gitlab, "maintenance/github-chiki"), chiki)
        self.git("reset", "--hard", main)
        rewritten = self.commit("rewritten")
        self.git("push", "--force", str(self.gitlab), "chiki")
        self.run_mirror()
        self.assertEqual(self.tip(self.github, "chiki"), rewritten)
        self.assertEqual(self.tip(self.gitlab, "maintenance/github-chiki"), rewritten)

    def test_external_divergence_fails_closed(self) -> None:
        old = self.tip(self.gitlab, "maintenance/github-main")
        self.commit("external")
        self.git("push", str(self.github), "main")
        with self.assertRaises(RuntimeError):
            self.run_mirror()
        self.assertEqual(self.tip(self.gitlab, "maintenance/github-main"), old)

    def test_recover_after_push_before_marker_update(self) -> None:
        self.git("checkout", "chiki")
        desired = self.commit("next")
        self.git("push", str(self.gitlab), "chiki")
        original = mirror_github.git

        def fail_marker(
            repo: Path, *args: str, env: dict[str, str] | None = None
        ) -> str:
            if (
                args[0] == "push"
                and str(self.gitlab) in args
                and any(
                    arg.startswith(":refs/heads/maintenance/github-intent-")
                    for arg in args
                )
            ):
                msg = "marker update failed"
                raise RuntimeError(msg)
            return original(repo, *args, env=env)

        with (
            patch.object(mirror_github, "git", side_effect=fail_marker),
            self.assertRaises(RuntimeError),
        ):
            self.run_mirror()
        self.assertEqual(self.tip(self.github, "chiki"), desired)
        later = self.commit("later")
        self.git("push", str(self.gitlab), "chiki")
        self.run_mirror()
        self.assertEqual(self.tip(self.github, "chiki"), later)
        self.assertEqual(self.tip(self.gitlab, "maintenance/github-chiki"), later)

    def test_retry_intent_then_mirror_newer_source(self) -> None:
        self.git("checkout", "chiki")
        intended = self.commit("next")
        self.git(
            "push",
            str(self.gitlab),
            "chiki",
            "main:maintenance/github-intent-main",
            "chiki:maintenance/github-intent-chiki",
        )
        later = self.commit("later")
        self.git("push", str(self.gitlab), "chiki")
        self.run_mirror()
        self.assertNotEqual(intended, later)
        self.assertEqual(self.tip(self.github, "chiki"), later)
        self.assertEqual(self.tip(self.gitlab, "maintenance/github-chiki"), later)
        refs = self.git(
            "ls-remote", str(self.gitlab), "refs/heads/maintenance/github-intent-*"
        )
        self.assertEqual(refs, "")

    def test_retry_lease_rejects_concurrent_external_change(self) -> None:
        self.git("checkout", "chiki")
        self.commit("intended")
        self.git(
            "push",
            str(self.gitlab),
            "chiki",
            "main:maintenance/github-intent-main",
            "chiki:maintenance/github-intent-chiki",
        )
        self.git("checkout", "main")
        external = self.commit("external")
        original = mirror_github.git

        def race(repo: Path, *args: str, env: dict[str, str] | None = None) -> str:
            if args[0] == "push" and str(self.github) in args:
                self.git("push", str(self.github), "main:chiki")
            return original(repo, *args, env=env)

        with (
            patch.object(mirror_github, "git", side_effect=race),
            self.assertRaises(RuntimeError),
        ):
            self.run_mirror()
        self.assertEqual(self.tip(self.github, "chiki"), external)
        self.assertNotEqual(
            self.tip(self.github, "chiki"), self.tip(self.gitlab, "chiki")
        )
        self.assertEqual(
            self.tip(self.gitlab, "maintenance/github-intent-chiki"),
            self.tip(self.gitlab, "chiki"),
        )

    def test_partial_intent_fails_closed(self) -> None:
        self.git("push", str(self.gitlab), "main:maintenance/github-intent-main")
        with self.assertRaises(RuntimeError):
            self.run_mirror()

    def test_unrecorded_source_match_fails_closed(self) -> None:
        self.git("checkout", "chiki")
        self.commit("external")
        self.git("push", str(self.gitlab), "chiki")
        self.git("push", str(self.github), "chiki")
        with self.assertRaises(RuntimeError):
            self.run_mirror()

    def test_inconsistent_source_rejected(self) -> None:
        self.git("checkout", "main")
        self.commit("main only")
        self.git("push", str(self.gitlab), "main")
        with self.assertRaises(RuntimeError):
            self.run_mirror()

    def test_missing_marker_rejected(self) -> None:
        self.git("push", str(self.gitlab), ":maintenance/github-main")
        with self.assertRaises(RuntimeError):
            self.run_mirror()


class AuthenticationTest(unittest.TestCase):
    def test_source_credentials_are_scoped(self) -> None:
        env = {
            "GL_TOKEN": "gl-secret",
            "GITHUB_MIRROR_TOKEN": "gh-secret",
            "GIT_ASKPASS": "askpass",
        }
        calls: list[dict[str, str]] = []

        def capture_fetch(
            _repo: Path, *args: str, env: dict[str, str] | None = None
        ) -> str:
            if args[0] == "fetch":
                assert env is not None
                calls.append(env)
                msg = "stop"
                raise RuntimeError(msg)
            return ""

        with (
            patch.object(mirror_github, "git", side_effect=capture_fetch),
            self.assertRaises(RuntimeError),
        ):
            mirror(
                "https://gitlab.example/group/repo.git",
                "https://github.com/smdex/llm-agents.nix.git",
                env,
            )
        source = calls[0]
        self.assertNotIn("GITHUB_MIRROR_TOKEN", source)
        self.assertNotIn("GIT_ASKPASS", source)
        self.assertEqual(
            source["GIT_CONFIG_KEY_0"], "http.https://gitlab.example/.extraHeader"
        )
        self.assertEqual(
            source["GIT_CONFIG_VALUE_0"],
            "Authorization: Basic b2F1dGgyOmdsLXNlY3JldA==",
        )

    def test_url_validation(self) -> None:
        valid = {
            "GITLAB_MIRROR_URL": "https://gitlab.example/group/repo.git",
            "GITHUB_MIRROR_URL": "https://github.com/smdex/llm-agents.nix.git",
            "GL_TOKEN": "gl-secret",
            "GITHUB_MIRROR_TOKEN": "gh-secret",
        }
        with (
            patch.dict(os.environ, valid, clear=True),
            patch.object(mirror_github, "mirror") as run,
        ):
            self.assertEqual(mirror_github.main(), 0)
            run.assert_called_once()
        for key, value in [
            ("GITHUB_MIRROR_URL", "https://github.com/other/repo"),
            ("GITHUB_MIRROR_URL", "https://github.com/smdex/llm-agents.nix.git?x=1"),
            ("GITLAB_MIRROR_URL", "https://user:pass@gitlab.example/repo"),
            ("GITLAB_MIRROR_URL", "http://gitlab.example/repo"),
            ("GL_TOKEN", ""),
        ]:
            with (
                self.subTest(key=key, value=value),
                patch.dict(os.environ, {**valid, key: value}, clear=True),
                patch.object(mirror_github, "mirror") as run,
            ):
                self.assertEqual(mirror_github.main(), 1)
                run.assert_not_called()


if __name__ == "__main__":
    unittest.main()
