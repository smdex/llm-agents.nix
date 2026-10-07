#!/usr/bin/env python3

"""Run with python3 packages/jcode/update_test.py."""

import tempfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import update


def check() -> None:
    """Stale release tags must not set the version, and failures must roll back."""
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        package = root / "package.nix"
        package.write_text("original")
        (root / "Cargo.toml").write_text('[package]\nversion = "9.8.7"\n')

        def run(command: list[str], **_kwargs: object) -> None:
            if "--src-only" in command:
                assert "--version=branch=main" in command
                package.write_text("stale-tag-version")
            else:
                assert "--version=9.8.7" in command
                assert "--no-src" in command
                package.write_text("correct-cargo-version")

        with (
            patch.object(update, "__file__", str(root / "update.py")),
            patch.object(
                update, "nix_command", return_value=SimpleNamespace(stdout=directory)
            ),
            patch.object(update, "run_command", side_effect=run),
        ):
            update.main()
            assert package.read_text() == "correct-cargo-version"
            with patch.object(
                update, "nix_command", side_effect=RuntimeError("fetch failed")
            ):
                failed = False
                try:
                    update.main()
                except RuntimeError:
                    failed = True
                assert failed, "updater swallowed the failure"
            assert package.read_text() == "correct-cargo-version"
    print("Fork branch, Cargo version, and rollback checks passed")


if __name__ == "__main__":
    check()
