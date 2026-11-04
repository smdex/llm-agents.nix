"""Tests for the update entry point."""

import os
import subprocess
import unittest
from unittest import mock

from discovery import discover_packages
from update import git_has_changes, refuse_downgrade


class TestRefuseDowngrade(unittest.TestCase):
    def test_upgrades_and_unchanged_versions_pass(self) -> None:
        refuse_downgrade("qwen-code", "0.24.1", "0.25.1")
        refuse_downgrade("qwen-code", "0.24.1", "0.24.1")
        refuse_downgrade("oh-my-opencode", "5.0.0-beta.86", "5.0.0")

    def test_downgrade_fails(self) -> None:
        with self.assertRaises(SystemExit):
            refuse_downgrade("qwen-code", "0.24.1", "0.21.2")


class TestDiscovery(unittest.TestCase):
    def test_nix_failure_propagates(self) -> None:
        result = subprocess.CompletedProcess(["nix"], 1, "", "evaluation failed")
        with (
            mock.patch("discovery.subprocess.run", return_value=result),
            self.assertRaises(subprocess.CalledProcessError) as error,
        ):
            discover_packages(None, "x86_64-linux")
        self.assertEqual(error.exception.stderr, "evaluation failed")


class TestGitChanges(unittest.TestCase):
    def test_base_ref_and_return_codes(self) -> None:
        error_code = 128
        for env, base in [
            ({}, "origin/main"),
            ({"UPDATE_BASE_REF": "origin/chiki"}, "origin/chiki"),
        ]:
            for code in (0, 1, error_code):
                result = subprocess.CompletedProcess(["git"], code)
                with (
                    mock.patch.dict(os.environ, env, clear=True),
                    mock.patch("update.run", return_value=result) as run,
                ):
                    if code == error_code:
                        with self.assertRaises(subprocess.CalledProcessError):
                            git_has_changes()
                    else:
                        self.assertEqual(git_has_changes(), code == 1)
                    run.assert_called_once_with(
                        ["git", "diff", "--quiet", base], check=False
                    )


if __name__ == "__main__":
    unittest.main()
