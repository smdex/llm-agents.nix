"""Tests for the update entry point."""

import os
import subprocess
import sys
import unittest
from pathlib import Path

from update import refuse_downgrade


class TestRefuseDowngrade(unittest.TestCase):
    def test_entry_point_imports_without_pythonpath(self) -> None:
        env = {key: value for key, value in os.environ.items() if key != "PYTHONPATH"}
        result = subprocess.run(
            [sys.executable, str(Path(__file__).with_name("update.py")), "--help"],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_upgrades_and_unchanged_versions_pass(self) -> None:
        refuse_downgrade("qwen-code", "0.24.1", "0.25.1")
        refuse_downgrade("qwen-code", "0.24.1", "0.24.1")
        refuse_downgrade("oh-my-opencode", "5.0.0-beta.86", "5.0.0")

    def test_downgrade_fails(self) -> None:
        with self.assertRaises(SystemExit):
            refuse_downgrade("qwen-code", "0.24.1", "0.21.2")


if __name__ == "__main__":
    unittest.main()
