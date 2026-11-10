"""Tests for the fork update driver: env hygiene and publish gating."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path
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


class StashTest(unittest.TestCase):
    def test_stashed_updater_imports_outside_repo(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            stashed = driver.stash_ci_scripts(Path(tmp))
            result = subprocess.run(
                ["python3", str(stashed / "update.py"), "--help"],
                cwd=tmp,
                env={"PATH": os.environ["PATH"]},
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(result.returncode, 0, result.stderr)

    def test_updater_receives_target_branch(self) -> None:
        result = mock.Mock(returncode=1, stdout="", stderr="failed")
        with mock.patch.object(driver, "run", return_value=result) as run:
            driver.run_updater("paseo", Path("ci"), default_branch="chiki")
        self.assertEqual(run.call_args.kwargs["env"]["UPDATE_BASE_REF"], "origin/chiki")


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


class MainSelectionTest(unittest.TestCase):
    def test_explicit_shared_package_and_branch(self) -> None:
        config = mock.Mock()
        result = mock.Mock(stdout="packages/shared\npackages/fork\n")
        with (
            mock.patch.object(
                driver.sys,
                "argv",
                ["driver", "--branch", "chiki", "--packages", "shared"],
            ),
            mock.patch.object(driver, "resolve_config", return_value=config),
            mock.patch.object(driver, "run", return_value=result) as run,
            mock.patch.object(driver, "fork_packages", return_value=["fork"]) as fork,
            mock.patch.object(driver, "stash_ci_scripts"),
            mock.patch.object(
                driver, "discover_updates", return_value=[{"name": "shared"}]
            ) as discover,
            mock.patch.object(driver, "process_package", return_value=True) as process,
        ):
            driver.main()
        fork.assert_called_once_with(explicit=True, branch="chiki")
        self.assertEqual(discover.call_args.args[0], ["shared"])
        self.assertEqual(process.call_args.kwargs["default_branch"], "chiki")
        self.assertEqual(process.call_args.kwargs["allowlist"], frozenset({"shared"}))
        self.assertTrue(
            any("origin/chiki" in call.args[0] for call in run.call_args_list)
        )

    def test_discovery_uses_resolved_environment_branch(self) -> None:
        with (
            mock.patch.dict(
                os.environ, {"DEFAULT_BRANCH": "chiki", "FORK_REF": "origin/main"}
            ),
            mock.patch.object(driver.sys, "argv", ["driver"]),
            mock.patch.object(driver, "resolve_config"),
            mock.patch.object(driver, "run"),
            mock.patch.object(driver, "fork_packages", return_value=[]) as fork,
        ):
            driver.main()
        fork.assert_called_once_with(explicit=False, branch="chiki")

    def test_unknown_package_is_rejected(self) -> None:
        with (
            mock.patch.object(driver.sys, "argv", ["driver", "--packages", "missing"]),
            mock.patch.object(driver, "resolve_config"),
            mock.patch.object(
                driver, "run", return_value=mock.Mock(stdout="packages/fork\n")
            ),
            mock.patch.object(driver, "fork_packages", return_value=["fork"]),
            self.assertRaisesRegex(ValueError, "Unknown packages: missing"),
        ):
            driver.main()


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

    def test_allowlist_only_exempts_named_shared_packages(self) -> None:
        with (
            mock.patch.object(
                driver.gitlab_mr,
                "allowed_roots",
                return_value=("packages/shared/", "packages/other/"),
            ),
            mock.patch.object(
                driver,
                "run",
                return_value=mock.Mock(stdout="packages/shared\npackages/other\n"),
            ),
        ):
            with self.assertRaisesRegex(RuntimeError, "packages/other"):
                driver.require_fork_only_companions(
                    "shared", allowlist=frozenset({"shared"})
                )
            driver.require_fork_only_companions(
                "shared", allowlist=frozenset({"shared", "other"})
            )


class ValidateMrTest(unittest.TestCase):
    def test_targeted_build_requires_matching_target(self) -> None:
        script = Path(driver.REPO_ROOT / "scripts/ci/validate-mr.sh")
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp)
            log = bindir / "nix.log"
            (bindir / "git").write_text("#!/bin/sh\nexit 0\n")
            (bindir / "nix").write_text(
                '#!/bin/sh\nprintf "%s\\n" "$*" >> "$TEST_LOG"\n'
            )
            for name in ("git", "nix"):
                (bindir / name).chmod(0o755)
            for source, target, builds in (
                ("update/foo", "main", True),
                ("update-branch/chiki/foo", "chiki", True),
                ("update-branch/main/foo", "chiki", False),
                ("update-branch/chiki/foo/bar", "chiki", False),
                ("update/foo", "chiki", False),
            ):
                log.write_text("")
                env = dict(
                    os.environ,
                    PATH=f"{tmp}:{os.environ['PATH']}",
                    TEST_LOG=str(log),
                    MR_SOURCE_BRANCH=source,
                    MR_TARGET_BRANCH=target,
                )
                subprocess.run(
                    ["bash", str(script)], env=env, check=True, capture_output=True
                )
                self.assertEqual(
                    "build --accept-flake-config --no-link .#foo" in log.read_text(),
                    builds,
                    source,
                )


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

    def test_branch_and_allowlist_are_forwarded(self) -> None:
        with (
            mock.patch.object(driver, "prepare_branch") as prepare,
            mock.patch.object(driver, "require_fork_only_companions") as guard,
            mock.patch.object(
                driver,
                "run_updater",
                return_value={"updated": "true", "new_version": "0.12.0"},
            ) as updater,
        ):
            self.assertTrue(
                driver.process_package(
                    self.item,
                    stashed_ci=None,
                    publish=self.publish,
                    default_branch="chiki",
                    allowlist=frozenset({"paseo"}),
                )
            )  # type: ignore[arg-type]
        updater.assert_called_once_with("paseo", None, default_branch="chiki")
        prepare.assert_called_once_with("paseo", default_branch="chiki")
        guard.assert_called_once_with(
            "paseo", allowlist=frozenset({"paseo"}), default_branch="chiki"
        )
        assert self.publish.kwargs is not None
        self.assertEqual(self.publish.kwargs["default_branch"], "chiki")

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
