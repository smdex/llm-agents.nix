"""Regression checks for OpenHuman's nested source submodules."""

# Standalone package tests do not form a Python package.
# ruff: noqa: INP001

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "openhuman_update", Path(__file__).with_name("update.py")
)
assert spec is not None
assert spec.loader is not None
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class SubmodulePinsTest(unittest.TestCase):
    def test_nested_source_modules_skip_wiki(self) -> None:
        trees = {
            ("tinyhumansai/openhuman", "v0.64.15"): {"vendor/tinyagents": "agents"},
            ("tinyhumansai/tinyagents", "agents"): {"vendor/tinytools": "tools"},
            ("tinyhumansai/tinytools", "tools"): {},
        }
        modules = {
            ("tinyhumansai/openhuman", "v0.64.15"): {
                "vendor/tinyagents": "tinyhumansai/tinyagents",
            },
            ("tinyhumansai/tinyagents", "agents"): {
                "vendor/tinytools": "tinyhumansai/tinytools",
                "wiki": "tinyhumansai/tinyagents.wiki",
            },
        }
        with (
            patch.object(
                update, "gitlink_revs", side_effect=lambda slug, rev: trees[slug, rev]
            ),
            patch.object(
                update,
                "parse_gitmodules",
                side_effect=lambda slug, rev: modules[slug, rev],
            ),
        ):
            pins = update.submodule_pins("v0.64.15")
        self.assertEqual(
            set(pins), {"vendor/tinyagents", "vendor/tinyagents/vendor/tinytools"}
        )
        self.assertEqual(pins["vendor/tinyagents/vendor/tinytools"]["rev"], "tools")

    def test_truncated_tree_is_rejected(self) -> None:
        with (
            patch.object(
                update, "fetch_json", return_value={"tree": [], "truncated": True}
            ),
            self.assertRaisesRegex(ValueError, "truncated"),
        ):
            update.gitlink_revs("owner/repo", "rev")

    def test_gitlinks_exclude_documentation(self) -> None:
        tree = {
            "tree": [
                {"path": "vendor/source", "sha": "source", "mode": "160000"},
                {"path": "wiki", "sha": "docs", "mode": "160000"},
            ]
        }
        with patch.object(update, "fetch_json", return_value=tree):
            self.assertEqual(
                update.gitlink_revs("owner/repo", "rev"), {"vendor/source": "source"}
            )


if __name__ == "__main__":
    unittest.main()
