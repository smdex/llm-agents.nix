"""Tests for the update entry point."""

import os
import select
import signal
import subprocess
import sys
import unittest
from contextlib import suppress
from pathlib import Path
from unittest import mock

from discovery import discover_packages
from update import git_has_changes, refuse_downgrade, run_update_command


class TestUpdateOutput(unittest.TestCase):
    def test_child_failure_still_fails_update(self) -> None:
        with (
            mock.patch(
                "update.subprocess.run",
                return_value=subprocess.CompletedProcess(["updater"], 1),
            ) as run,
            self.assertRaises(SystemExit) as error,
        ):
            run_update_command(["updater"], "update failed")
        self.assertEqual(error.exception.code, 1)
        run.assert_called_once_with(
            ["updater"], stderr=subprocess.STDOUT, text=True, check=False
        )

    @unittest.skipUnless(os.name == "posix", "process-group cleanup requires POSIX")
    def test_child_output_is_visible_before_updater_finishes(self) -> None:
        child = "import time; print('updater progress', flush=True); time.sleep(30)"
        parent = (
            "import sys; from update import run_update_command; "
            f"run_update_command([sys.executable, '-c', {child!r}], 'failed')"
        )
        env = os.environ | {
            "PYTHONPATH": os.pathsep.join(
                [str(Path(__file__).parent), os.environ.get("PYTHONPATH", "")]
            )
        }
        process = subprocess.Popen(
            [sys.executable, "-c", parent],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
            start_new_session=True,
        )
        try:
            assert process.stdout is not None
            ready, _, _ = select.select([process.stdout], [], [], 5)
            self.assertTrue(ready, "updater buffered child progress until exit")
            self.assertEqual(process.stdout.readline(), b"updater progress\n")
            self.assertIsNone(process.poll())
        finally:
            with suppress(ProcessLookupError):
                os.killpg(process.pid, signal.SIGTERM)
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                with suppress(ProcessLookupError):
                    os.killpg(process.pid, signal.SIGKILL)
                process.communicate(timeout=5)


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
