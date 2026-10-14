#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update PyPI native wheels, selecting filenames from its artifact array.

The declarative manifest updater accepts keyed platform objects, while PyPI
publishes an array of filenames with nested SHA-256 digests.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import fetch_json, load_hashes, save_hashes
from updater.hash import hex_to_sri

HASHES_FILE = Path(__file__).with_name("hashes.json")
PLATFORMS = {
    "x86_64-linux": "manylinux_2_17_x86_64",
    "aarch64-darwin": "macosx_11_0_arm64",
    "any": "any",
}


def main() -> None:
    """Pin all supported native wheels from the current PyPI release."""
    metadata = fetch_json("https://pypi.org/pypi/hol-guard/json")
    if not isinstance(metadata, dict):
        raise TypeError
    version = metadata["info"]["version"]
    artifacts = {entry["filename"]: entry for entry in metadata["urls"]}
    hashes = {
        system: hex_to_sri(
            artifacts[f"hol_guard-{version}-py3-none-{platform}.whl"]["digests"][
                "sha256"
            ]
        )
        for system, platform in PLATFORMS.items()
    }
    data = {"version": version, "hashes": hashes}
    if HASHES_FILE.exists() and load_hashes(HASHES_FILE) == data:
        print(f"Already up to date: {version}")
        return
    save_hashes(HASHES_FILE, data)
    print(f"Updated HOL Guard to {version}")


if __name__ == "__main__":
    main()
