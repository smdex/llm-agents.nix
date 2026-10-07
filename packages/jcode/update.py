#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#nix-update --command python3

"""Track the fork's main branch, using Cargo's version rather than stale tags."""

import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from updater.nix import nix_command, run_command


def main() -> None:
    """Update the source pin and dependency hash without changing repositories."""
    package = Path(__file__).with_name("package.nix")
    original = package.read_text()
    try:
        run_command(
            ["nix-update", "--flake", "jcode", "--version=branch=main", "--src-only"],
            capture_output=False,
        )
        source = nix_command(
            ["build", ".#jcode.src", "--no-link", "--print-out-paths"]
        ).stdout.strip()
        with (Path(source) / "Cargo.toml").open("rb") as manifest:
            version = tomllib.load(manifest)["package"]["version"]
        run_command(
            ["nix-update", "--flake", "jcode", f"--version={version}", "--no-src"],
            capture_output=False,
        )
    except BaseException:
        package.write_text(original)
        raise


if __name__ == "__main__":
    main()
