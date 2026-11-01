"""Keep ccusage pricing pinned to either upstream lockfile representation."""

import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "ccusage_update", Path(__file__).resolve().parents[2] / "packages/ccusage/update.py"
)
assert SPEC is not None
assert SPEC.loader is not None
UPDATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE)
REV = "467847b2e9da67dd1c4ef43ff7d95ca56c013fa3"
URL = f"https://raw.githubusercontent.com/BerriAI/litellm/{REV}/{UPDATE.PRICING_FILE}"


class PricingPinTest(unittest.TestCase):
    def resolve(self, locked: dict[str, str]) -> str:
        lock = json.dumps({"nodes": {"litellm": {"locked": locked}}})
        with patch.object(UPDATE, "fetch_text", return_value=lock):
            result = UPDATE.resolve_litellm_rev("20.0.46")
            assert isinstance(result, str)
            return result

    def test_git_revision(self) -> None:
        self.assertEqual(self.resolve({"type": "github", "rev": REV}), REV)

    def test_pinned_file_url(self) -> None:
        self.assertEqual(self.resolve({"type": "file", "url": URL}), REV)

    def test_reject_missing_or_unpinned_pricing(self) -> None:
        for locked in (
            {},
            {"rev": "main"},
            {"type": "file", "url": URL.replace(REV, "main")},
            {"type": "file", "url": URL.replace("BerriAI", "other")},
            {"type": "file", "url": URL + "?other=true"},
        ):
            with self.subTest(locked=locked), self.assertRaises(ValueError):
                self.resolve(locked)


if __name__ == "__main__":
    unittest.main()
