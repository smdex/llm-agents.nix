"""Tests for the vibe-kanban custom updater (packages/vibe-kanban/update.py).

Pipeline 9425 regression: the licence-zip URL was constructed by
pattern and 404'd when the latest release's assets were named
differently. The updater must select assets from the release's own
asset list and fail with a clear message when the expected asset is
absent. All network and nix machinery is mocked.
"""

# ruff: noqa: INP001 # standalone test beside the package's update.py

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path
from typing import TYPE_CHECKING
from unittest import mock

if TYPE_CHECKING:
    from types import ModuleType


def load_updater() -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        "vibe_kanban_update", Path(__file__).with_name("update.py")
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


LATEST_RELEASE = {
    "tag_name": "v0.1.45-20261101000000",
    "tarball_url": "https://api.github.com/repos/BloopAI/vibe-kanban/tarball/v0.1.45-20261101000000",
    "assets": [
        {
            "name": "Vibe-Kanban-0.1.45-x86_64.msi",
            "browser_download_url": "https://example/msi",
        },
        {
            "name": "vibe-kanban-v0.1.45-20261101000000.zip",
            "browser_download_url": "https://example/licence.zip",
        },
    ],
}


class ReleaseAssetSelectionTest(unittest.TestCase):
    def setUp(self) -> None:
        self.updater = load_updater()

    def test_exact_asset_name_is_selected(self) -> None:
        url = self.updater.release_asset_url(
            LATEST_RELEASE, "vibe-kanban-v0.1.45-20261101000000.zip"
        )
        self.assertEqual(url, "https://example/licence.zip")

    def test_prefix_match_is_not_enough(self) -> None:
        # A differently-cased or partial name must NOT be used.
        with self.assertRaises(RuntimeError):
            self.updater.release_asset_url(LATEST_RELEASE, "vibe-kanban-0.1.45.zip")

    def test_missing_asset_lists_available_names(self) -> None:
        with self.assertRaises(RuntimeError) as caught:
            self.updater.release_asset_url(LATEST_RELEASE, "gone.zip")
        message = str(caught.exception)
        self.assertIn("gone.zip", message)
        self.assertIn("vibe-kanban-v0.1.45-20261101000000.zip", message)
        self.assertIn("Vibe-Kanban-0.1.45-x86_64.msi", message)

    def test_release_without_assets_is_an_explicit_error(self) -> None:
        with self.assertRaises(RuntimeError) as caught:
            self.updater.release_asset_url({"tag_name": "v1", "assets": []}, "x.zip")
        self.assertIn("available assets: none", str(caught.exception))


class UpdaterFlowTest(unittest.TestCase):
    def test_fetch_latest_release_parses_tag_and_semver(self) -> None:
        updater = load_updater()
        with mock.patch.object(updater, "fetch_json", return_value=LATEST_RELEASE):
            tag, semver, release = updater.fetch_latest_release()
        self.assertEqual(tag, "v0.1.45-20261101000000")
        self.assertEqual(semver, "0.1.45")
        self.assertEqual(release["tag_name"], tag)

    def test_up_to_date_short_circuits_before_any_url_use(self) -> None:
        updater = load_updater()
        with (
            mock.patch.object(
                updater, "fetch_json", return_value=LATEST_RELEASE
            ) as fetch,
            mock.patch.object(
                updater, "load_hashes", return_value={"version": "0.1.45"}
            ),
            mock.patch.object(updater, "calculate_url_hash") as calc,
        ):
            updater.main()
        fetch.assert_called_once()
        calc.assert_not_called()


if __name__ == "__main__":
    unittest.main()
