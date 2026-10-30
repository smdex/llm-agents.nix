#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for vibe-kanban package.

vibe-kanban is the rare GitHub project where the release tag carries a
timestamp suffix (`v0.1.44-20260424091429`). nix-update can't parse
that, and the package layers a second prebuilt-zip asset on top of the
normal source + cargoHash + npmDepsHash for a baked-in react-virtuoso
licence key, so we drive the update through hashes.json by hand.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_json,
    load_hashes,
    save_hashes,
    should_update,
    update_dependency_hash,
)
from updater.hash import DUMMY_SHA256_HASH

HASHES_FILE = Path(__file__).parent / "hashes.json"
OWNER = "BloopAI"
REPO = "vibe-kanban"


def fetch_latest_release() -> tuple[str, str, dict[str, object]]:
    """Return (tag, semver, release) of the latest release.

    Tags look like `v0.1.44-20260424091429`; strip the `v` and timestamp
    suffix to derive the semver used as `version`.
    """
    data = fetch_json(f"https://api.github.com/repos/{OWNER}/{REPO}/releases/latest")
    if not isinstance(data, dict):
        msg = f"Expected dict from GitHub API, got {type(data)}"
        raise TypeError(msg)
    tag: str = data["tag_name"]
    return tag, tag.lstrip("v").split("-", 1)[0], data


def release_asset_url(release: dict[str, object], expected_name: str) -> str:
    """Exact-match an asset by name and return its download URL.

    Constructing asset URLs by pattern 404s whenever upstream names a
    release's assets differently (live pipeline 9425). Matching the
    release's own asset list is the only correct source of truth; a
    missing asset is an explicit error listing what exists — never a
    guessed URL and never a silent skip.
    """
    raw_assets = release.get("assets")
    assets: list[dict[str, object]] = [
        item
        for item in (raw_assets if isinstance(raw_assets, list) else [])
        if isinstance(item, dict)
    ]
    for asset in assets:
        if asset.get("name") == expected_name:
            url = str(asset.get("browser_download_url") or "")
            if url:
                return url
    names = ", ".join(sorted(str(a.get("name")) for a in assets)) or "none"
    message = (
        f"release {release.get('tag_name')} has no asset {expected_name!r}; "
        f"available assets: {names}"
    )
    raise RuntimeError(message)


def main() -> None:
    """Update vibe-kanban hashes to the latest BloopAI release."""
    data = load_hashes(HASHES_FILE)
    tag, latest, release = fetch_latest_release()
    print(f"Current: {data['version']}, Latest: {latest} (tag {tag})")
    if not should_update(data["version"], latest):
        print("Already up to date")
        return

    src_url = str(release["tarball_url"])
    zip_url = release_asset_url(release, f"vibe-kanban-{tag}.zip")

    new_data = {
        "version": latest,
        "tag": tag,
        "hash": calculate_url_hash(src_url, unpack=True),
        "cargoHash": DUMMY_SHA256_HASH,
        "npmDepsHash": DUMMY_SHA256_HASH,
        "releaseZipHash": calculate_url_hash(zip_url, unpack=False),
    }
    save_hashes(HASHES_FILE, new_data)

    # cargoHash and npmDepsHash both fall out of FOD build failures, so
    # trigger them sequentially.
    for key in ("cargoHash", "npmDepsHash"):
        update_dependency_hash(".#vibe-kanban", key, HASHES_FILE, new_data)

    print(f"Updated to {latest} (tag {tag})")


if __name__ == "__main__":
    main()
