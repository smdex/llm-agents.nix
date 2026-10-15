"""Tests for fork-packages.sh: directory set difference vs upstream."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "fork-packages.sh"


class GitRepo:
    """A scratch git repository with helper commands."""

    def __init__(self, path: Path) -> None:
        self.path = path
        path.mkdir(parents=True, exist_ok=True)
        self.run(["git", "init", "-q", "-b", "main"])
        self.run(["git", "config", "user.email", "test@example.com"])
        self.run(["git", "config", "user.name", "Test"])

    def run(self, cmd: list[str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            cmd, cwd=self.path, check=True, capture_output=True, text=True
        )

    def add_package(self, name: str, *, content: str = "x\n") -> None:
        package = self.path / "packages" / name
        package.mkdir(parents=True, exist_ok=True)
        (package / "package.nix").write_text(content)

    def commit(self, message: str) -> None:
        self.run(["git", "add", "-A"])
        self.run(["git", "commit", "-q", "-m", message])


def run_script(
    cwd: Path, env_extra: dict[str, str]
) -> subprocess.CompletedProcess[str]:
    env = {**os.environ, **env_extra}
    # "bash <script>" bypasses the nix shebang so tests run without nix.
    return subprocess.run(
        ["bash", str(SCRIPT)],
        cwd=cwd,
        env=env,
        check=False,
        capture_output=True,
        text=True,
    )


class ForkPackagesTest(unittest.TestCase):
    def setUp(self) -> None:
        self._temp = tempfile.TemporaryDirectory()
        self.addCleanup(self._temp.cleanup)
        root = Path(self._temp.name)

        upstream = GitRepo(root / "upstream")
        upstream.add_package("shared-package")
        upstream.add_package("upstream-only")
        upstream.commit("upstream base")

        # The fork's own remote (origin), seeded from upstream: a bare
        # clone so the fork work tree can push its commit back to it.
        subprocess.run(
            [
                "git",
                "clone",
                "-q",
                "--bare",
                str(root / "upstream"),
                str(root / "origin"),
            ],
            check=True,
            capture_output=True,
            text=True,
        )

    def _setup_fork(self) -> Path:
        """Return a fork clone whose origin is the scratch fork remote."""
        root = Path(self._temp.name)
        fork_path = root / "fork"
        subprocess.run(
            [
                "git",
                "clone",
                "-q",
                "--origin",
                "origin",
                str(root / "origin"),
                str(fork_path),
            ],
            check=True,
            capture_output=True,
            text=True,
        )
        fork = GitRepo(fork_path)
        fork.add_package("shared-package", content="modified by fork\n")
        fork.add_package("fork-added")
        fork.commit("fork additions")
        # fork-packages.sh diffs origin/main (what CI sees after a full
        # clone), so the fork commit must be pushed to the origin remote.
        fork.run(["git", "push", "-q", "origin", "main"])
        return fork_path

    def test_directory_set_difference_yields_fork_additions_only(self) -> None:
        fork_path = self._setup_fork()
        result = run_script(
            fork_path,
            {
                "UPSTREAM_URL": str(Path(self._temp.name) / "upstream"),
                "UPSTREAM_REF": "main",
                "DEFAULT_BRANCH": "main",
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["fork-added"])

    def test_selection_rejects_non_fork_packages(self) -> None:
        fork_path = self._setup_fork()
        result = run_script(
            fork_path,
            {
                "FORK_UPDATE_PACKAGES": "shared-package",
                "UPSTREAM_URL": str(Path(self._temp.name) / "upstream"),
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a fork addition", result.stderr)

    def test_no_fork_additions_is_empty(self) -> None:
        root = Path(self._temp.name)
        plain = root / "plain"
        subprocess.run(
            ["git", "clone", "-q", str(root / "upstream"), str(plain)],
            check=True,
            capture_output=True,
            text=True,
        )
        result = run_script(
            plain,
            {"UPSTREAM_URL": str(root / "upstream"), "DEFAULT_BRANCH": "main"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
