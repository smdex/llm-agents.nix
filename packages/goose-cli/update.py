#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for goose-cli package.

Bumps the goose version, source hash and cargoHash in hashes.json.
Legacy librustyV8 hashes remain pinned for the separate goosed package;
current goose-cli no longer depends on V8.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    load_hashes,
    save_hashes,
    should_update,
    update_dependency_hash,
)
from updater.hash import DUMMY_SHA256_HASH

HASHES_FILE = Path(__file__).parent / "hashes.json"
# Upstream moved from block/goose to aaif-goose/goose.
OWNER = "aaif-goose"
REPO = "goose"


def main() -> None:
    """Update the goose-cli package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)
    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    src_url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"
    data["version"] = latest
    data["hash"] = calculate_url_hash(src_url, unpack=True)
    data["cargoHash"] = DUMMY_SHA256_HASH
    save_hashes(HASHES_FILE, data)

    update_dependency_hash(".#goose-cli", "cargoHash", HASHES_FILE, data)

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
