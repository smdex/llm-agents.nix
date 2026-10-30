"""Keep legacy goosed V8 pins independent of current goose-cli updates."""

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


class GooseCliUpdateTest(unittest.TestCase):
    def test_update_without_v8_preserves_legacy_pins(self) -> None:
        script = Path(__file__).resolve().parents[2] / "packages/goose-cli/update.py"
        spec = importlib.util.spec_from_file_location("goose_cli_update", script)
        assert spec is not None
        assert spec.loader is not None
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        legacy = {"version": "145.0.0", "hashes": {"x86_64-linux": "legacy-hash"}}
        data = {"version": "1.55.0", "librustyV8": legacy.copy()}
        with (
            patch.object(module, "load_hashes", return_value=data),
            patch.object(module, "fetch_github_latest_release", return_value="1.57.0"),
            patch.object(module, "calculate_url_hash", return_value="new-source-hash"),
            patch.object(module, "save_hashes") as save,
            patch.object(module, "update_dependency_hash") as dependency,
        ):
            module.main()
        self.assertEqual(data["version"], "1.57.0")
        self.assertEqual(data["hash"], "new-source-hash")
        self.assertEqual(data["librustyV8"], legacy)
        save.assert_called_once_with(module.HASHES_FILE, data)
        dependency.assert_called_once_with(
            ".#goose-cli", "cargoHash", module.HASHES_FILE, data
        )


if __name__ == "__main__":
    unittest.main()
