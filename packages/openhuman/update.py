#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for the openhuman package.

Upstream is a pnpm monorepo with two cargo worlds and nine git submodules,
and the desktop shell embeds a pinned CEF binary distribution.  This script:

1. resolves the latest ``v<semver>`` tag (tags regularly outrun GitHub
   releases here),
2. prefetches the main tarball and every gitlink recorded in the tag's tree,
3. re-pins the CEF dist: crate version from the tag's ``Cargo.lock``,
   archive name/sha1 from the Spotify CDN index, tarball hash by prefetch,
4. recomputes the fixed-output hashes (pnpm deps, both cargo vendor sets,
   both CEF dist repackages) via the dummy-hash build loop.

Only ``hashes.json`` is touched; ``package.nix`` reads everything from it.
"""

import re
import sys
from functools import cmp_to_key
from pathlib import Path
from typing import Any, cast

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    DepHasher,
    calculate_url_hash,
    fetch_json,
    fetch_text,
    load_hashes,
    save_hashes,
)
from updater.hash import DUMMY_SHA256_HASH
from updater.nix import nix_build
from updater.version import compare_versions

HASHES_FILE = Path(__file__).parent / "hashes.json"
OWNER = "tinyhumansai"
REPO = "openhuman"

# path-in-tree -> GitHub repo (mirrors ``submoduleRepos`` in package.nix;
# the hashes.json key is the path's basename).
SUBMODULE_REPOS: dict[str, str] = {
    "app/src-tauri/vendor/tauri-cef": "tauri-cef",
    "app/src-tauri/vendor/tauri-plugin-notification": "tauri-plugin-notification",
    "vendor/tinyagents": "tinyagents",
    "vendor/tinyflows": "tinyflows",
    "vendor/tinycortex": "tinycortex",
    "vendor/tinyjuice": "tinyjuice",
    "vendor/tinychannels": "tinychannels",
    "vendor/tinyplace": "tiny.place",
    "vendor/tinyhumans-sdk": "sdk",
}

CEF_INDEX = "https://cef-builds.spotifycdn.com/index.json"


class NestedHashStore:
    """StateStore over dotted paths into hashes.json (``a.b.c``)."""

    def __init__(self, path: Path, data: dict[str, Any]) -> None:
        """Bind the store to a hashes.json path and its parsed data."""
        self._path = path
        self._data = data

    def _parent(self, key: str) -> dict[str, Any]:
        """Resolve the dict holding a dotted path's leaf key."""
        node: Any = self._data
        for part in key.split(".")[:-1]:
            node = node[part]
        return cast("dict[str, Any]", node)

    def read(self) -> dict[str, Any]:
        """Return the in-memory state."""
        return self._data

    def write(self, data: dict[str, Any]) -> None:
        """Replace and persist the whole state."""
        self._data = data
        save_hashes(self._path, self._data)

    def get(self, key: str) -> str | None:
        """Return the string at a dotted path, or None."""
        value = self._parent(key).get(key.rsplit(".", 1)[-1])
        return value if isinstance(value, str) else None

    def stage_dummy(self, key: str, dummy: str) -> None:
        """Write a placeholder hash at a dotted path and persist."""
        self._parent(key)[key.rsplit(".", 1)[-1]] = dummy
        save_hashes(self._path, self._data)

    def rollback(self, key: str, original: str | None) -> None:
        """Restore the pre-staging value at a dotted path and persist."""
        leaf = key.rsplit(".", 1)[-1]
        if original is None:
            self._parent(key).pop(leaf, None)
        else:
            self._parent(key)[leaf] = original
        save_hashes(self._path, self._data)

    def commit(self, key: str, value: str) -> None:
        """Write the final value at a dotted path and persist."""
        self.stage_dummy(key, value)


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


def gitlink_revs(tag: str) -> dict[str, str]:
    """Map submodule path -> pinned rev, from the tag's (recursive) tree."""
    tree = fetch_json(
        f"https://api.github.com/repos/{OWNER}/{REPO}/git/trees/{tag}?recursive=1",
    )
    if not isinstance(tree, dict) or not isinstance(tree.get("tree"), list):
        msg = "unexpected tree API response"
        raise TypeError(msg)
    if tree.get("truncated"):
        msg = "tree listing truncated; per-subtree queries needed"
        raise ValueError(msg)
    revs = {
        str(entry["path"]): str(entry["sha"])
        for entry in tree["tree"]
        if entry.get("mode") == "160000"
    }
    missing = set(SUBMODULE_REPOS) - set(revs)
    if missing:
        msg = f"tag {tag} is missing expected gitlinks: {sorted(missing)}"
        raise ValueError(msg)
    return revs


def prefetch_github_archive(repo: str, rev: str) -> str:
    """fetchFromGitHub-compatible SRI hash of a tag/commit tarball."""
    return calculate_url_hash(
        f"https://github.com/{OWNER}/{repo}/archive/{rev}.tar.gz",
        unpack=True,
    )


def cef_pins(tag: str) -> tuple[str, dict[str, dict[str, str]]]:
    """CEF crate version + per-platform {name, sha1} for the tag.

    Returns the crate version (``146.4.1+146.0.9``) and, per platform in
    ``linux64``/``linuxarm64``, the CDN archive name and sha1.
    """
    lock = fetch_text(
        f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{tag}/app/src-tauri/Cargo.lock",
    )
    m = re.search(
        r'^\s*name = "cef-dll-sys"\n\s*version = "([^"]+)"', lock, re.MULTILINE
    )
    if not m:
        msg = f"cef-dll-sys not found in {tag} app Cargo.lock"
        raise ValueError(msg)
    crate_version = m.group(1)
    cef_version = crate_version.split("+", 1)[1]

    index = fetch_json(CEF_INDEX)
    if not isinstance(index, dict):
        msg = "unexpected CEF index shape"
        raise TypeError(msg)
    pins: dict[str, dict[str, str]] = {}
    for platform in ("linux64", "linuxarm64"):
        versions = index.get(platform, {}).get("versions")
        if not isinstance(versions, list):
            msg = f"CEF index lacks {platform}.versions"
            raise TypeError(msg)
        entry = next(
            (
                v
                for v in versions
                if isinstance(v, dict)
                and str(v.get("cef_version", "")).startswith(cef_version + "+")
            ),
            None,
        )
        if entry is None:
            msg = f"CEF {cef_version} not found for {platform}"
            raise ValueError(msg)
        archive = next(
            f
            for f in entry["files"]
            if isinstance(f, dict) and f.get("type") == "minimal"
        )
        if not (isinstance(archive.get("name"), str) and archive.get("sha1")):
            msg = f"CEF minimal archive for {platform} lacks name/sha1"
            raise ValueError(msg)
        pins[platform] = {
            "name": str(archive["name"]),
            "sha1": str(archive["sha1"]),
        }
    return crate_version, pins


def main() -> None:
    """Update hashes.json to the latest upstream tag."""
    data = load_hashes(HASHES_FILE)
    current = str(data["version"])
    latest = latest_tag()

    print(f"openhuman: current={current}, latest={latest}")

    if current == latest:
        print("Already up to date")
        return

    store = NestedHashStore(HASHES_FILE, data)

    # 1) Main source.
    print(f"Prefetching {REPO} v{latest}...")
    data["version"] = latest
    data["hash"] = prefetch_github_archive(REPO, f"v{latest}")
    save_hashes(HASHES_FILE, data)

    # 2) Submodules at the tag's gitlinks.
    revs = gitlink_revs(f"v{latest}")
    for path, repo in SUBMODULE_REPOS.items():
        name = path.rsplit("/", 1)[-1]
        rev = revs[path]
        old = data["submodules"].get(name, {})
        if old.get("rev") == rev and old.get("hash"):
            print(f"submodule {name}: unchanged at {rev}")
            continue
        print(f"submodule {name}: {old.get('rev', '?')} -> {rev}")
        data["submodules"][name] = {
            "rev": rev,
            "hash": prefetch_github_archive(repo, rev),
        }
    save_hashes(HASHES_FILE, data)

    # 3) CEF pin.
    crate_version, pins = cef_pins(f"v{latest}")
    print(f"CEF: crate {crate_version}")
    data["cef"]["crateVersion"] = crate_version
    data["cef"]["cefVersion"] = crate_version.split("+", 1)[1]
    for platform, pin in pins.items():
        archive = data["cef"]["archives"][platform]
        if archive.get("name") == pin["name"]:
            archive["sha1"] = pin["sha1"]
            continue
        print(f"CEF {platform}: {archive.get('name', '?')} -> {pin['name']}")
        archive["name"] = pin["name"]
        archive["sha1"] = pin["sha1"]
        archive["tarballHash"] = calculate_url_hash(
            f"https://cef-builds.spotifycdn.com/{pin['name']}",
        )
        archive["distHash"] = DUMMY_SHA256_HASH
    save_hashes(HASHES_FILE, data)

    # 4) Fixed-output hashes via the dummy-hash build loop. pnpmDeps first
    # (independent of the tree), then the cargo sets (need fullSrc = main +
    # submodules correct), then the CEF dist repackage.
    for key, attr in (
        ("pnpmDeps", ".#openhuman.pnpmDeps"),
        ("cargoCliDeps", ".#openhuman.cargoDepsCli"),
        ("cargoAppDeps", ".#openhuman.cargoDepsApp"),
        ("cef.archives.linux64.distHash", ".#openhuman.cefDist"),
        ("cef.archives.linuxarm64.distHash", ".#openhuman.cefDistArm64"),
    ):
        print(f"Hashing {key} via {attr}...")
        DepHasher(store, attr, build=nix_build).hash(key)

    print(f"openhuman updated to {latest}")


if __name__ == "__main__":
    main()
