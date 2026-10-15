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
