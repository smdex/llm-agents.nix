#!/usr/bin/env python3

"""Update script for the oh-my-codex-smdex package."""

import sys
from pathlib import Path
from typing import Any, cast

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_dependency_hash,
    calculate_url_hash,
    fetch_json,
    load_hashes,
    save_hashes,
    should_update,
)
from updater.hash import DUMMY_SHA256_HASH
from updater.nix import NixCommandError

OWNER = "smdex"
REPO = "oh-my-codex"
BRANCH = "main"
HASHES_FILE = Path(__file__).parent / "hashes.json"
PACKAGE_ATTR = ".#oh-my-codex-smdex"


def fetch_branch_state() -> tuple[str, str]:
    """Fetch the latest version and revision from the fork's main branch."""
    ref_data = fetch_json(
        f"https://api.github.com/repos/{OWNER}/{REPO}/git/ref/heads/{BRANCH}"
    )
    if not isinstance(ref_data, dict):
        msg = f"Expected dict for branch ref, got {type(ref_data)}"
        raise TypeError(msg)

    obj = cast("dict[str, Any]", ref_data["object"])
    rev = cast("str", obj["sha"])

    package_json = fetch_json(
        f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{rev}/package.json"
    )
    if not isinstance(package_json, dict):
        msg = f"Expected dict for package.json, got {type(package_json)}"
        raise TypeError(msg)

    return cast("str", package_json["version"]), rev


def main() -> None:
    """Update oh-my-codex-smdex to the fork's latest main branch state."""
    current_data = load_hashes(HASHES_FILE)
    current_version = cast("str", current_data["version"])
    current_rev = cast("str", current_data["rev"])
    latest_version, latest_rev = fetch_branch_state()

    print(
        f"Current: {current_version} ({current_rev[:8]}), "
        f"Latest: {latest_version} ({latest_rev[:8]})"
    )

    if not should_update(current_version, latest_version) and current_rev == latest_rev:
        print("Already up to date")
        return

    url = f"https://github.com/{OWNER}/{REPO}/archive/{latest_rev}.tar.gz"

    print("Calculating source hash...")
    source_hash = calculate_url_hash(url, unpack=True)

    data = {
        "version": latest_version,
        "rev": latest_rev,
        "hash": source_hash,
        "cargoHash": DUMMY_SHA256_HASH,
        "npmDepsHash": cast("str", current_data["npmDepsHash"]),
    }
    save_hashes(HASHES_FILE, data)

    try:
        cargo_hash = calculate_dependency_hash(
            f"{PACKAGE_ATTR}.native.exploreHarness",
            "cargoHash",
            HASHES_FILE,
            data,
        )
        data["cargoHash"] = cargo_hash
        save_hashes(HASHES_FILE, data)

        data["npmDepsHash"] = DUMMY_SHA256_HASH
        save_hashes(HASHES_FILE, data)

        npm_deps_hash = calculate_dependency_hash(
            PACKAGE_ATTR,
            "npmDepsHash",
            HASHES_FILE,
            data,
        )
        data["npmDepsHash"] = npm_deps_hash
        save_hashes(HASHES_FILE, data)
    except (ValueError, NixCommandError) as e:
        print(f"Error: {e}")
        return

    print(f"Updated to {latest_version} ({latest_rev})")


if __name__ == "__main__":
    main()
