#!/usr/bin/env python3
"""Check vendored source metadata remains usable without IFD."""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "autolith_updater", Path(__file__).with_name("update.py")
)
assert spec is not None
assert spec.loader is not None
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class MetadataTests(unittest.TestCase):
    def test_lock_is_inlined_and_nix_interpolation_escaped(self) -> None:
        source = 'let\n  qlotLock = builtins.readFile "${src}/qlfile.lock";\n  version = lib.removeSuffix "\\n" (builtins.readFile "${src}/VERSION");\n  fffSourceCommit = "old";\nin null'
        texts = {
            "package.nix": source,
            "commit": "a" * 40,
            "VERSION": "1.0.0",
            "qlfile.lock": '("${literal}" "two\'\'quotes")',
        }
        with patch.object(
            updater, "fetch_text", side_effect=lambda url: texts[url.rsplit("/", 1)[1]]
        ):
            result = updater.vendor_upstream_nix("v1.0.0")
        self.assertNotIn("builtins.readFile", result)
        self.assertIn("''${literal}", result)
        self.assertIn("two'''quotes", result)
        self.assertIn("a" * 40, result)
        self.assertIn('version = "1.0.0"', result)

    def test_crane_pin_is_written_before_formatter_evaluates_package(self) -> None:
        crane = {
            "type": "github",
            "owner": "ipetkov",
            "repo": "crane",
            "rev": "a" * 40,
            "narHash": "sha256-test",
        }
        with tempfile.TemporaryDirectory() as directory:
            hashes = Path(directory) / "hashes.json"
            hashes.write_text(json.dumps({"version": "1.0.0", "hash": "old"}))

            def check_metadata(*_args: object, **_kwargs: object) -> None:
                self.assertEqual(json.loads(hashes.read_text())["crane"], crane)

            with (
                patch.object(updater, "HASHES", hashes),
                patch.object(updater, "UPSTREAM_NIX", Path(directory) / "upstream.nix"),
                patch.object(
                    updater, "fetch_github_latest_release", return_value="1.0.1"
                ),
                patch.object(updater, "vendor_upstream_nix", return_value="{}"),
                patch.object(updater, "calculate_url_hash", return_value="new"),
                patch.object(
                    updater,
                    "fetch_text",
                    return_value=json.dumps({"nodes": {"crane": {"locked": crane}}}),
                ),
                patch.object(updater, "run_command", side_effect=check_metadata),
            ):
                updater.main()
            self.assertEqual(json.loads(hashes.read_text())["version"], "1.0.1")


if __name__ == "__main__":
    unittest.main()
