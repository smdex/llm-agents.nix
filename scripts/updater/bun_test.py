"""Bun's Git integrity slot must not be mistaken for an npm package."""

import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from updater.bun import regenerate_bun_nix


class BunGitLockTest(unittest.TestCase):
    def test_git_integrity_is_removed_only_from_the_converter_copy(self) -> None:
        entries = {
            "git": [
                "omowright@github:code-yeongyu/omowright#c06d203",
                {},
                "archive",
                "sha512-integrity",
            ],
            "scoped": [
                "@scope/pkg@git+https://example.org/repo#abcdef",
                {},
                "archive",
                "sha512-integrity",
            ],
            "old": ["old@github:owner/repo#abcdef", {}, "archive"],
            "npm": ["npm@1.2.3", "", {}, "sha512-integrity"],
            "workspace": ["local@workspace:packages/local"],
            "unrecognized": [
                "odd@github:owner/repo#abcdef",
                {},
                "archive",
                "not-integrity",
            ],
        }
        original = json.dumps({"lockfileVersion": 1, "packages": entries})
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "bun.lock"
            source.write_text(original)
            converted: list[object] = []

            def run(
                command: list[str], **_kwargs: object
            ) -> subprocess.CompletedProcess[str]:
                if "--lock-file" in command:
                    data = json.loads(
                        Path(command[command.index("--lock-file") + 1]).read_text()
                    )
                    converted.append(data)
                    self.assertEqual(len(data["packages"]["git"]), 3)
                    self.assertEqual(len(data["packages"]["scoped"]), 3)
                    for name in ["old", "npm", "workspace", "unrecognized"]:
                        self.assertEqual(data["packages"][name], entries[name])
                return subprocess.CompletedProcess(
                    command, 0, stdout=original, stderr=""
                )

            with patch("updater.bun.run_command", side_effect=run):
                regenerate_bun_nix(source, root / "bun.nix", root)
            self.assertEqual(len(converted), 1)
            self.assertEqual(source.read_text(), original)


if __name__ == "__main__":
    unittest.main()
