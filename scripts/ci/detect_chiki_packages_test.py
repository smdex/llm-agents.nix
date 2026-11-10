"""Tests for detecting changed chiki package directories."""

import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "detect-chiki-packages.sh"


class DetectChikiPackagesTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "test@example.com")
        self.git("config", "user.name", "Test")
        for name in ("override", "deleted", "unchanged"):
            self.package(name, "base")
        self.commit("base")
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def git(self, *args: str) -> None:
        subprocess.run(["git", *args], cwd=self.repo, check=True, capture_output=True)

    def package(self, name: str, content: str) -> None:
        path = self.repo / "packages" / name / "package.nix"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)

    def commit(self, message: str) -> None:
        self.git("add", "-A")
        self.git("commit", "-qm", message)

    def detect(self) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.repo,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_added_overridden_companion_and_deleted(self) -> None:
        self.package("override", "changed")
        self.package("added", "new")
        self.package("companion", "new")
        (self.repo / "packages/deleted/package.nix").unlink()
        (self.repo / "other").write_text("ignored")
        self.commit("changes")
        self.git("update-ref", "refs/remotes/origin/chiki", "HEAD")
        # The working tree must not determine whether a package exists on chiki.
        (self.repo / "packages/added/package.nix").unlink()
        result = self.detect()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.split(), ["added", "companion", "override"])

    def test_empty_diff_and_missing_ref(self) -> None:
        self.git("update-ref", "refs/remotes/origin/chiki", "HEAD")
        result = self.detect()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.git("update-ref", "-d", "refs/remotes/origin/chiki")
        self.assertNotEqual(self.detect().returncode, 0)


if __name__ == "__main__":
    unittest.main()
