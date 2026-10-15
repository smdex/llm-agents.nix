"""Tests for the fork update driver: env hygiene and publish gating."""

from __future__ import annotations

import os
import unittest
from typing import Any
from unittest import mock

from ci import update_fork_packages as driver


class SanitizedUpdaterEnvTest(unittest.TestCase):
    def test_strips_all_credentials(self) -> None:
        env = driver.sanitized_updater_env(
            {
                "GL_TOKEN": "gl",
                "CI_JOB_TOKEN": "job",
                "GH_TOKEN": "gh",
                "GITHUB_TOKEN": "github",
                "PATH": "/usr/bin",
                "CI_REPOSITORY_URL": "https://user:token@gitlab.local/project",
                "DEPLOY_SECRET": "secret",
                "GIT_CONFIG_VALUE_5": "Authorization: secret",
            }
        )
        for leaked in (
            "GL_TOKEN",
            "CI_JOB_TOKEN",
            "GH_TOKEN",
            "GITHUB_TOKEN",
            "CI_REPOSITORY_URL",
            "DEPLOY_SECRET",
            "GIT_CONFIG_VALUE_5",
        ):
            self.assertNotIn(leaked, env, f"{leaked} must not reach the updater")
        self.assertEqual(env["PATH"], "/usr/bin")

    def test_disables_git_hooks_and_fsmonitor(self) -> None:
        env = driver.sanitized_updater_env({})
        self.assertEqual(env["GIT_CONFIG_COUNT"], "2")
        self.assertEqual(env["GIT_CONFIG_KEY_0"], "core.hooksPath")
        self.assertEqual(env["GIT_CONFIG_VALUE_0"], "/dev/null")
        self.assertEqual(env["GIT_CONFIG_VALUE_1"], "false")

    def test_extra_values_do_not_reintroduce_credentials(self) -> None:
        env = driver.sanitized_updater_env({"GL_TOKEN": "leak"})
        self.assertNotIn("GL_TOKEN", env)


class ForkPackagesTest(unittest.TestCase):
    def test_selection_is_validated_by_detection_script(self) -> None:
        env = {"FORK_UPDATE_PACKAGES": "paseo pi-perplexity"}
        with (
            mock.patch.dict(os.environ, env, clear=False),
            mock.patch.object(
                driver,
                "run",
                return_value=mock.Mock(returncode=0, stdout="paseo\npi-perplexity\n"),
            ) as run,
        ):
            self.assertEqual(driver.fork_packages(), ["paseo", "pi-perplexity"])
        run.assert_called_once()


class CompanionScopeTest(unittest.TestCase):
    def test_upstream_companion_rejected_before_updating(self) -> None:
        with (
            mock.patch.object(
                driver.gitlab_mr,
                "allowed_roots",
                return_value=("packages/fork/", "packages/shared/"),
            ),
            mock.patch.object(
                driver, "run", return_value=mock.Mock(stdout="packages/shared\n")
            ),
            self.assertRaisesRegex(RuntimeError, "upstream-owned"),
        ):
            driver.require_fork_only_companions("fork")


class RecordingPublish:
    """Publish stand-in recording its call."""

    def __init__(self, result: str = "created") -> None:
        self.result = result
        self.kwargs: dict[str, Any] | None = None

    def __call__(self, **kwargs: Any) -> str:
        self.kwargs = kwargs
        return self.result


class ProcessPackageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.item = {"name": "paseo", "current_version": "0.11.0"}
        self.publish = RecordingPublish()

    def run_process(self, outputs: dict[str, str] | None) -> bool:
        with (
            mock.patch.object(driver, "prepare_branch"),
            mock.patch.object(driver, "require_fork_only_companions"),
            mock.patch.object(driver, "run_updater", return_value=outputs),
            mock.patch.object(driver.gitlab_mr, "publish_package_update", self.publish),
            mock.patch.dict(os.environ, {}, clear=False),
        ):
            return driver.process_package(self.item, stashed_ci=None)  # type: ignore[arg-type]

    def test_no_changes_publishes_nothing(self) -> None:
        self.assertTrue(self.run_process({"updated": "false"}))
        self.assertIsNone(self.publish.kwargs)

    def test_updater_failure_reports_failure(self) -> None:
        self.assertFalse(self.run_process(None))
        self.assertIsNone(self.publish.kwargs)

    def test_upgrade_is_published(self) -> None:
        self.assertTrue(
            self.run_process(
                {"updated": "true", "new_version": "0.11.2", "changelog": "https://c"}
            )
        )
        assert self.publish.kwargs is not None
        self.assertEqual(self.publish.kwargs["new_version"], "0.11.2")
        self.assertEqual(self.publish.kwargs["current_version"], "0.11.0")

    def test_downgrade_is_not_published(self) -> None:
        self.assertTrue(
            self.run_process(
                {"updated": "true", "new_version": "0.10.0", "changelog": ""}
            )
        )
        self.assertIsNone(self.publish.kwargs)

    def test_downgrade_published_when_explicitly_allowed(self) -> None:
        env = {"ALLOW_DOWNGRADE": "1"}
        with mock.patch.dict(os.environ, env, clear=False):
            self.assertTrue(
                self.run_process(
                    {"updated": "true", "new_version": "0.10.0", "changelog": ""}
                )
            )
        assert self.publish.kwargs is not None
        self.assertEqual(self.publish.kwargs["new_version"], "0.10.0")


if __name__ == "__main__":
    unittest.main()
