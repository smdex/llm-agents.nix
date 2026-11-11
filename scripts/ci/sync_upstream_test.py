"""Exercise upstream rebases and conflict policy using scratch local remotes."""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("sync-upstream.sh")


class SyncTest(unittest.TestCase):
    def git(self, repo: Path, *args: str) -> str:
        return subprocess.run(
            ["git", "-C", str(repo), *args], check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit(self, repo: Path, name: str, content: str) -> None:
        file = repo / name
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(content)
        self.git(repo, "add", "--all")
        self.git(repo, "commit", "-qm", "test change")

    def setUp(self) -> None:
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.upstream = self.root / "upstream"
        self.upstream.mkdir()
        self.git(self.upstream, "init", "-q", "-b", "main")
        self.git(self.upstream, "config", "user.name", "Test")
        self.git(self.upstream, "config", "user.email", "test@example.com")
        self.commit(self.upstream, "README.md", "base\n")
        self.commit(self.upstream, "packages/shared/package.nix", "base\n")
        self.commit(self.upstream, "config.txt", "base\n")
        generator = self.upstream / "scripts/generate-package-docs.nu"
        generator.parent.mkdir()
        generator.write_text("#!/bin/sh\nexit 0\n")
        generator.chmod(0o755)
        self.git(self.upstream, "add", "--all")
        self.git(self.upstream, "commit", "-qm", "test generator")
        self.origin = self.root / "origin.git"
        self.git(
            self.root, "clone", "-q", "--bare", str(self.upstream), str(self.origin)
        )
        self.fork = self.root / "fork"
        self.git(self.root, "clone", "-q", str(self.origin), str(self.fork))
        self.git(self.fork, "config", "user.name", "Test")
        self.git(self.fork, "config", "user.email", "test@example.com")
        # No network requests: the workflow gate sees a completed upstream run.
        bin_dir = self.root / "bin"
        bin_dir.mkdir()
        curl = bin_dir / "curl"
        curl.write_text(
            '#!/bin/sh\nprintf \'{"workflow_runs":[{"status":"completed"}]}\\n\'\n'
        )
        curl.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{bin_dir}:{os.environ['PATH']}",
            "GL_PROJECT_URL": str(self.origin),
            "GL_TOKEN": "test-token",
            "UPSTREAM_URL": str(self.upstream),
            "DEFAULT_BRANCH": "main",
        }

    def sync(self) -> subprocess.CompletedProcess[str]:
        if shutil.which("jq") is None:
            self.skipTest("sync tests require jq")
        return subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.fork,
            env=self.env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_chiki_rebase_preserves_package_override(self) -> None:
        old_main = self.git(self.fork, "rev-parse", "HEAD")
        self.git(self.fork, "checkout", "-qb", "chiki")
        self.commit(self.fork, "packages/shared/package.nix", "chiki edit\n")
        self.git(
            self.fork,
            "push",
            "-q",
            "origin",
            "chiki",
            f"{old_main}:refs/heads/maintenance/chiki-base",
        )
        self.git(self.fork, "checkout", "-q", "main")
        self.commit(self.fork, "packages/shared/package.nix", "main edit\n")
        self.git(self.fork, "push", "-q", "origin", "main")
        main = self.git(self.origin, "rev-parse", "main")
        self.env["SYNC_BRANCH"] = "chiki"
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git(self.origin, "rev-parse", "main"), main)
        self.assertEqual(
            self.git(self.origin, "show", "chiki:packages/shared/package.nix"),
            "chiki edit",
        )
        self.git(self.origin, "merge-base", "--is-ancestor", "main", "chiki")
        self.assertEqual(
            self.git(self.origin, "rev-parse", "maintenance/chiki-base"), main
        )

    def test_chiki_requires_valid_old_main(self) -> None:
        self.git(self.fork, "checkout", "-qb", "chiki")
        self.commit(self.fork, "chiki.txt", "chiki\n")
        self.git(self.fork, "push", "-q", "origin", "chiki")
        old = self.git(self.origin, "rev-parse", "chiki")
        self.git(self.fork, "checkout", "-q", "main")
        self.commit(self.fork, "main.txt", "main\n")
        self.git(self.fork, "push", "-q", "origin", "main")
        self.env["SYNC_BRANCH"] = "chiki"
        self.assertNotEqual(self.sync().returncode, 0)
        self.git(
            self.fork, "push", "-q", "origin", "main:refs/heads/maintenance/chiki-base"
        )
        self.assertNotEqual(self.sync().returncode, 0)
        self.assertEqual(self.git(self.origin, "rev-parse", "chiki"), old)

    def test_chiki_retry_uses_durable_base_after_main_advances(self) -> None:
        old_main = self.git(self.fork, "rev-parse", "HEAD")
        self.git(self.fork, "checkout", "-qb", "chiki")
        self.commit(self.fork, "packages/shared/package.nix", "override\n")
        self.git(
            self.fork,
            "push",
            "-q",
            "origin",
            "chiki",
            f"{old_main}:refs/heads/maintenance/chiki-base",
        )
        self.git(self.fork, "checkout", "-q", "main")
        self.commit(self.fork, "main.txt", "first\n")
        self.git(self.fork, "push", "-q", "origin", "main")
        self.env["SYNC_BRANCH"] = "chiki"
        first = self.sync()
        self.assertEqual(first.returncode, 0, first.stderr)
        self.git(self.fork, "checkout", "-q", "main")
        self.git(self.fork, "reset", "--hard", old_main)
        self.commit(self.fork, "main.txt", "second\n")
        self.git(self.fork, "push", "-q", "--force", "origin", "main")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git(self.origin, "rev-parse", "maintenance/chiki-base"),
            self.git(self.origin, "rev-parse", "main"),
        )
        self.git(self.origin, "merge-base", "--is-ancestor", "main", "chiki")

    def test_chiki_rebases_onto_rewritten_main_from_marker(self) -> None:
        common = self.git(self.fork, "rev-parse", "HEAD")
        self.commit(self.fork, "old-main.txt", "old main\n")
        marker = self.git(self.fork, "rev-parse", "HEAD")
        self.git(self.fork, "checkout", "-qb", "chiki")
        self.commit(self.fork, "packages/shared/package.nix", "chiki override\n")
        self.git(
            self.fork,
            "push",
            "-q",
            "origin",
            "chiki",
            f"{marker}:refs/heads/maintenance/chiki-base",
        )
        self.git(self.fork, "checkout", "-q", "main")
        self.git(self.fork, "reset", "--hard", common)
        self.commit(self.fork, "new-main.txt", "rewritten main\n")
        self.git(self.fork, "push", "-q", "--force", "origin", "main")
        main = self.git(self.origin, "rev-parse", "main")
        self.env["SYNC_BRANCH"] = "chiki"
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.git(self.origin, "merge-base", "--is-ancestor", main, "chiki")
        self.assertEqual(
            self.git(self.origin, "rev-parse", "maintenance/chiki-base"), main
        )
        self.assertEqual(
            self.git(self.origin, "show", "chiki:packages/shared/package.nix"),
            "chiki override",
        )
        self.assertEqual(
            self.git(self.origin, "ls-tree", "--name-only", "chiki", "old-main.txt"), ""
        )
        self.assertEqual(
            self.git(self.origin, "rev-list", "--count", "main..chiki"), "1"
        )

    def test_chiki_noop_updates_marker(self) -> None:
        old = self.git(self.fork, "rev-parse", "HEAD")
        self.commit(self.fork, "main.txt", "main\n")
        self.git(
            self.fork,
            "push",
            "-q",
            "origin",
            "main",
            "main:chiki",
            f"{old}:refs/heads/maintenance/chiki-base",
        )
        self.env["SYNC_BRANCH"] = "chiki"
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git(self.origin, "rev-parse", "maintenance/chiki-base"),
            self.git(self.origin, "rev-parse", "main"),
        )

    def test_chiki_rejects_main_rollback(self) -> None:
        old_main = self.git(self.fork, "rev-parse", "HEAD")
        self.commit(self.fork, "main.txt", "new main\n")
        marker = self.git(self.fork, "rev-parse", "HEAD")
        self.git(self.fork, "checkout", "-qb", "chiki")
        self.commit(self.fork, "override.txt", "override\n")
        chiki = self.git(self.fork, "rev-parse", "HEAD")
        self.git(
            self.fork,
            "push",
            "-q",
            "origin",
            "chiki",
            f"{marker}:refs/heads/maintenance/chiki-base",
        )
        self.env["SYNC_BRANCH"] = "chiki"
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("older than maintenance/chiki-base", result.stderr)
        self.assertEqual(self.git(self.origin, "rev-parse", "main"), old_main)
        self.assertEqual(self.git(self.origin, "rev-parse", "chiki"), chiki)
        self.assertEqual(
            self.git(self.origin, "rev-parse", "maintenance/chiki-base"), marker
        )

    def test_chiki_marker_race_rejects_both_updates(self) -> None:
        old = self.git(self.fork, "rev-parse", "HEAD")
        previous = self.git(self.fork, "rev-parse", "HEAD^")
        script = (
            "#!/bin/sh\n"
            f"git --git-dir='{self.origin}' update-ref refs/heads/maintenance/chiki-base {previous}\n"
        )
        self.git(self.fork, "checkout", "-qb", "chiki")
        self.commit(self.fork, "scripts/generate-package-docs.nu", script)
        self.git(
            self.fork,
            "push",
            "-q",
            "origin",
            "chiki",
            f"{old}:refs/heads/maintenance/chiki-base",
        )
        before = self.git(self.origin, "rev-parse", "chiki")
        self.git(self.fork, "checkout", "-q", "main")
        self.commit(self.fork, "main.txt", "main\n")
        self.git(self.fork, "push", "-q", "origin", "main")
        main = self.git(self.origin, "rev-parse", "main")
        self.env["SYNC_BRANCH"] = "chiki"
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git(self.origin, "rev-parse", "chiki"), before)
        self.assertEqual(
            self.git(self.origin, "rev-parse", "maintenance/chiki-base"), previous
        )
        self.assertEqual(self.git(self.origin, "rev-parse", "main"), main)

    def test_invalid_branch_is_rejected(self) -> None:
        self.env["SYNC_BRANCH"] = "other"
        self.assertNotEqual(self.sync().returncode, 0)

    def test_rebases_fork_additions(self) -> None:
        self.commit(self.fork, "packages/fork/package.nix", "fork\n")
        self.git(self.fork, "push", "-q", "origin", "main")
        self.commit(self.upstream, "packages/shared/package.nix", "new upstream\n")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git(self.origin, "show", "main:packages/fork/package.nix"), "fork"
        )
        self.assertEqual(
            self.git(self.origin, "show", "main:packages/shared/package.nix"),
            "new upstream",
        )

    def test_push_uses_exact_url_and_isolates_credentials(self) -> None:
        url = "https://gitlab.example/group/project.git"
        self.git(self.fork, "config", "http.extraHeader", "Authorization: inherited")
        self.git(
            self.fork, "config", f"http.{url}.extraHeader", "Authorization: scoped"
        )
        self.git(self.fork, "config", "credential.helper", "inherited-helper")
        self.git(self.fork, "config", f"credential.{url}.helper", "scoped-helper")
        git = shutil.which("git")
        assert git is not None
        bash = shutil.which("bash")
        assert bash is not None
        wrapper = self.root / "bin/git"
        wrapper.write_text(
            f"#!{bash}\n"
            "if [[ $1 == push ]]; then\n"
            f'  "{git}" config --get-urlmatch http.extraHeader "$PUSH_URL" > "$CAPTURE"\n'
            f'  "{git}" config --get-urlmatch credential.helper "$PUSH_URL" >> "$CAPTURE"\n'
            '  printf "%s\\n" "$*" >> "$CAPTURE"\n'
            "  exit 0\n"
            "fi\n"
            f'exec "{git}" "$@"\n'
        )
        wrapper.chmod(0o755)
        self.env.update(
            GL_PROJECT_URL="https://gitlab.example/group/project/",
            PUSH_URL=url,
            CAPTURE=str(self.root / "capture"),
            GIT_CONFIG_COUNT="1",
            GIT_CONFIG_KEY_0="http.extraHeader",
            GIT_CONFIG_VALUE_0="Authorization: environment",
        )
        self.commit(self.upstream, "new.txt", "upstream\n")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = (self.root / "capture").read_text().splitlines()
        self.assertEqual(lines[0], "Authorization: Basic b2F1dGgyOnRlc3QtdG9rZW4=")
        self.assertEqual(lines[1], "")
        self.assertIn(url, lines[2])
        self.assertNotIn("test-token", result.stdout + result.stderr + lines[2])
        self.assertNotIn("b2F1dGgyOnRlc3QtdG9rZW4=", result.stdout + result.stderr)

    def test_shared_package_conflict_uses_upstream(self) -> None:
        self.commit(self.fork, "packages/shared/package.nix", "fork edit\n")
        self.git(self.fork, "push", "-q", "origin", "main")
        self.commit(self.upstream, "packages/shared/package.nix", "upstream edit\n")
        result = self.sync()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.git(self.origin, "show", "main:packages/shared/package.nix"),
            "upstream edit",
        )

    def test_unexpected_conflict_aborts_without_remote_change(self) -> None:
        self.commit(self.fork, "config.txt", "fork edit\n")
        self.git(self.fork, "push", "-q", "origin", "main")
        old = self.git(self.origin, "rev-parse", "main")
        self.commit(self.upstream, "config.txt", "upstream edit\n")
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.git(self.origin, "rev-parse", "main"), old)

    def test_concurrent_remote_change_rejects_lease(self) -> None:
        racer = self.root / "racer"
        self.git(self.root, "clone", "-q", str(self.origin), str(racer))
        self.git(racer, "config", "user.name", "Racer")
        self.git(racer, "config", "user.email", "racer@example.com")
        # The generator executes after the lease anchor was captured.
        script = (
            "#!/bin/sh\n"
            f"git -C '{racer}' commit -q --allow-empty -m concurrent\n"
            f"git -C '{racer}' push -q origin main\n"
        )
        self.commit(self.fork, "scripts/generate-package-docs.nu", script)
        self.git(self.fork, "push", "-q", "origin", "main")
        self.git(racer, "pull", "-q", "--ff-only")
        self.commit(self.upstream, "packages/shared/package.nix", "upstream edit\n")
        result = self.sync()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stale info", result.stderr)
        self.assertEqual(
            self.git(self.origin, "log", "-1", "--format=%s", "main"), "concurrent"
        )
