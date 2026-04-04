#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for goose-desktop package."""

import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_json,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import hex_to_sri

HASHES_FILE = Path(__file__).parent / "hashes.json"


def release_assets(version: str) -> dict[str, dict[str, Any]]:
    """Return release assets keyed by asset name."""
    data = fetch_json(
        f"https://api.github.com/repos/block/goose/releases/tags/v{version}"
    )
    if not isinstance(data, dict):
        msg = f"Expected dict from GitHub release API, got {type(data)}"
        raise TypeError(msg)
    assets = data.get("assets", [])
    if not isinstance(assets, list):
        msg = "Expected assets list from GitHub release API"
        raise TypeError(msg)
    return {
        asset["name"]: asset
        for asset in assets
        if isinstance(asset, dict) and isinstance(asset.get("name"), str)
    }


def asset_hash(asset: dict[str, Any]) -> str:
    """Get an SRI hash from a GitHub release asset."""
    digest = asset.get("digest")
    if isinstance(digest, str) and digest.startswith("sha256:"):
        return hex_to_sri(digest.removeprefix("sha256:"))

    url = asset.get("browser_download_url")
    if not isinstance(url, str):
        msg = f"Missing browser_download_url for asset {asset.get('name')}"
        raise TypeError(msg)
    return calculate_url_hash(url)


def main() -> None:
    """Update the goose-desktop package."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release("block", "goose")

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    asset_name = f"goose_{latest}_amd64.deb"
    asset = release_assets(latest).get(asset_name)
    if asset is None:
        msg = f"Missing expected release asset: {asset_name}"
        raise ValueError(msg)

    save_hashes(
        HASHES_FILE,
        {
            "version": latest,
            "hashes": {
                "x86_64-linux": asset_hash(asset),
            },
        },
    )

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
