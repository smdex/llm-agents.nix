#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update OpenHuman source, recursive vendor submodules and dependency hashes.

Upstream's tags outrun releases. Its CLI workspace and desktop crate have
separate Cargo locks, and source archives omit the nested vendor gitlinks.
No declarative updater currently handles this combination.
"""

import re
import sys
from functools import cmp_to_key
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    DepHasher,
    HashesJsonStore,
    calculate_url_hash,
    fetch_json,
    fetch_text,
    load_hashes,
    save_hashes,
)
from updater.nix import nix_build
from updater.version import compare_versions

HASHES_FILE = Path(__file__).parent / "hashes.json"
OWNER = "tinyhumansai"
REPO = "openhuman"


def latest_tag() -> str:
    """Highest ``v<semver>`` tag from the GitHub tags API."""
    tags = fetch_json(
        f"https://api.github.com/repos/{OWNER}/{REPO}/tags?per_page=100",
    )
    if not isinstance(tags, list):
        msg = "unexpected tags API response"
        raise TypeError(msg)
    versions = [
        m.group(1)
        for entry in tags
        if isinstance(entry, dict)
        and (m := re.fullmatch(r"v(\d+\.\d+\.\d+)", str(entry.get("name", ""))))
    ]
    if not versions:
        msg = f"no v<semver> tags found for {OWNER}/{REPO}"
        raise ValueError(msg)
    return max(versions, key=cmp_to_key(compare_versions))


def parse_gitmodules(slug: str, rev: str) -> dict[str, str]:
    """Map submodule paths to GitHub repositories at a pinned revision."""
    text = fetch_text(
        f"https://raw.githubusercontent.com/{slug}/{rev}/.gitmodules",
    )
    sections = re.split(r'(?m)^\s*\[submodule\s+"[^\"]+"\]', text)[1:]
    slugs: dict[str, str] = {}
    for section in sections:
        path = re.search(r"(?m)^\s*path\s*=\s*(\S+)", section)
        url = re.search(r"(?m)^\s*url\s*=\s*(\S+)", section)
        if path is None or url is None:
            msg = f".gitmodules section lacks path/url at {slug}/{rev}"
            raise ValueError(msg)
        match = re.fullmatch(
            r"https://github\.com/([^/\s]+)/([^/\s]+?)(?:\.git)?/?", url.group(1)
        )
        if match is None:
            msg = f"submodule {path.group(1)} has an unsupported URL: {url.group(1)}"
            raise ValueError(msg)
        slugs[path.group(1)] = f"{match.group(1)}/{match.group(2)}"
    return slugs


def gitlink_revs(slug: str, rev: str) -> dict[str, str]:
    """Find source gitlinks; documentation-only wiki submodules are omitted."""
    tree = fetch_json(
        f"https://api.github.com/repos/{slug}/git/trees/{rev}?recursive=1",
    )
    if not isinstance(tree, dict) or not isinstance(tree.get("tree"), list):
        msg = f"unexpected tree API response for {slug}/{rev}"
        raise TypeError(msg)
    if tree.get("truncated"):
        msg = f"tree listing truncated for {slug}/{rev}"
        raise ValueError(msg)
    return {
        str(entry["path"]): str(entry["sha"])
        for entry in tree["tree"]
        if entry.get("mode") == "160000" and str(entry["path"]).startswith("vendor/")
    }


def submodule_pins(tag: str) -> dict[str, dict[str, str]]:
    """Flatten recursive source submodules into paths relative to OpenHuman."""
    pins: dict[str, dict[str, str]] = {}

    def visit(slug: str, rev: str, prefix: str) -> None:
        revs = gitlink_revs(slug, rev)
        if not revs:
            return
        slugs = parse_gitmodules(slug, rev)
        orphans = set(revs) - set(slugs)
        if orphans:
            msg = (
                f"{slug}/{rev} has gitlinks missing from .gitmodules: {sorted(orphans)}"
            )
            raise ValueError(msg)
        for path, pinned_rev in sorted(revs.items()):
            child_slug = slugs[path]
            owner, repo = child_slug.split("/", 1)
            full_path = prefix + path
            pins[full_path] = {"owner": owner, "repo": repo, "rev": pinned_rev}
            visit(child_slug, pinned_rev, full_path + "/")

    visit(f"{OWNER}/{REPO}", tag, "")
    return pins


def prefetch_github_archive(slug: str, rev: str) -> str:
    """fetchFromGitHub-compatible SRI hash of a ``owner/repo`` tarball."""
    return calculate_url_hash(
        f"https://github.com/{slug}/archive/{rev}.tar.gz",
        unpack=True,
    )


def update_submodules(tag: str, data: dict[str, Any]) -> None:
    """Re-pin the hashes.json submodule set to the tag's gitlink tree.

    The set is derived from the tree, so upstream additions and removals
    are followed: new pins are prefetched, stale entries dropped.
    """
    old_submodules = data["submodules"]
    new_submodules: dict[str, Any] = {}
    for path, pin in sorted(submodule_pins(tag).items()):
        prev = old_submodules.get(path, {})
        if prev.get("rev") == pin["rev"] and prev.get("hash"):
            # Same commit; keep the pinned hash, refresh the repo location.
            prev["owner"], prev["repo"] = pin["owner"], pin["repo"]
            new_submodules[path] = prev
            print(f"submodule {path}: unchanged at {pin['rev']}")
            continue
        print(f"submodule {path}: {prev.get('rev', '?')} -> {pin['rev']}")
        new_submodules[path] = {
            "owner": pin["owner"],
            "repo": pin["repo"],
            "rev": pin["rev"],
            "hash": prefetch_github_archive(
                f"{pin['owner']}/{pin['repo']}", pin["rev"]
            ),
        }
    for gone in sorted(set(old_submodules) - set(new_submodules)):
        print(f"submodule {gone}: dropped (not in the tag's tree)")
    data["submodules"] = new_submodules
    save_hashes(HASHES_FILE, data)


def main() -> None:
    """Update hashes.json to the latest upstream tag."""
    data = load_hashes(HASHES_FILE)
    current = str(data["version"])
    latest = latest_tag()

    print(f"openhuman: current={current}, latest={latest}")

    if current == latest:
        print("Already up to date")
        return

    store = HashesJsonStore(HASHES_FILE, data=data)

    # 1) Main source.
    print(f"Prefetching {REPO} v{latest}...")
    data["version"] = latest
    data["hash"] = prefetch_github_archive(f"{OWNER}/{REPO}", f"refs/tags/v{latest}")
    save_hashes(HASHES_FILE, data)

    # 2) Submodules from the tag's gitlink tree.
    update_submodules(f"v{latest}", data)

    # The current desktop shell uses native Tauri/WebKitGTK, without CEF.
    data.pop("cef", None)
    save_hashes(HASHES_FILE, data)

    hash_jobs = [
        ("pnpmDeps", ".#openhuman.pnpmDeps"),
        ("cargoCliDeps", ".#openhuman.cargoDepsCli"),
        ("cargoAppDeps", ".#openhuman.cargoDepsApp"),
    ]
    for key, attr in hash_jobs:
        print(f"Hashing {key} via {attr}...")
        DepHasher(store, attr, build=nix_build).hash(key)

    print(f"openhuman updated to {latest}")


if __name__ == "__main__":
    main()
