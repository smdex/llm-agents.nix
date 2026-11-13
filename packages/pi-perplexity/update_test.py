#!/usr/bin/env python3
"""Run with: python3 packages/pi-perplexity/update_test.py."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "pplx_updater", Path(__file__).with_name("update.py")
)
assert spec is not None
assert spec.loader is not None
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)
run_update = vars(update)["update"]


class CliUpdaterTest(unittest.TestCase):
    """Keep independent CLI versions, immutable commits and rollback intact."""

    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.pkg = Path(self.folder.name)
        self.file = self.pkg / "hashes.json"
        self.original = {
            "version": "0.1.0",
            "rev": "a" * 40,
            "hash": "old-source",
            "bunDepsHash": "old-deps",
        }
        self.file.write_text(json.dumps(self.original))

    def test_current_cli_does_not_follow_plugin_tags_or_rebuild(self) -> None:
        with (
            patch.object(
                update,
                "fetch_json",
                side_effect=[{"sha": "a" * 40}, {"version": "0.1.0"}],
            ) as fetch,
            patch.object(update, "calculate_url_hash") as source,
        ):
            run_update(self.pkg)
        source.assert_not_called()
        self.assertIn("/package.json", fetch.call_args.args[0])
        self.assertNotIn("/cli/", fetch.call_args.args[0])
        self.assertEqual(json.loads(self.file.read_text()), self.original)

    def test_same_version_new_commit_refreshes_source_and_real_dependency_hasher(
        self,
    ) -> None:
        with (
            patch.object(
                update,
                "fetch_json",
                side_effect=[{"sha": "b" * 40}, {"version": "0.1.0"}],
            ),
            patch.object(update, "calculate_url_hash", return_value="new-source"),
            patch.object(update, "DepHasher") as hasher,
        ):
            run_update(self.pkg)
        self.assertEqual(json.loads(self.file.read_text())["rev"], "b" * 40)
        self.assertEqual(json.loads(self.file.read_text())["hash"], "new-source")
        self.assertEqual(hasher.call_args.args[1], ".#pi-perplexity.bunDeps")
        hasher.return_value.hash.assert_called_once_with("bunDepsHash")

    def test_bad_metadata_and_downgrade_leave_original(self) -> None:
        for responses in [
            [[]],
            [{"sha": "main"}],
            [{"sha": "b" * 40}, {"version": "${unsafe}"}],
            [{"sha": "b" * 40}, {"version": "0.0.9"}],
        ]:
            with (
                self.subTest(responses=responses),
                patch.object(update, "fetch_json", side_effect=responses),
                self.assertRaises(ValueError),
            ):
                run_update(self.pkg)
            self.assertEqual(json.loads(self.file.read_text()), self.original)

    def test_interrupted_dependency_hash_rolls_back_entire_update(self) -> None:
        def interrupt(_key: str) -> None:
            self.file.write_text('{"bunDepsHash": "dummy"}')
            raise KeyboardInterrupt

        with (
            patch.object(
                update,
                "fetch_json",
                side_effect=[{"sha": "b" * 40}, {"version": "0.1.0"}],
            ),
            patch.object(update, "calculate_url_hash", return_value="new-source"),
            patch.object(update, "DepHasher") as hasher,
        ):
            hasher.return_value.hash.side_effect = interrupt
            with self.assertRaises(KeyboardInterrupt):
                run_update(self.pkg)
        self.assertEqual(json.loads(self.file.read_text()), self.original)


if __name__ == "__main__":
    unittest.main()
