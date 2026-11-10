#!/usr/bin/env python3
"""Follow the published CLI commit/version, not the monorepo's Pi-plugin tags."""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))

from updater.deps import DepHasher
from updater.hash import calculate_url_hash
from updater.hashes_file import load_hashes, save_hashes
from updater.http import fetch_json
from updater.store import HashesJsonStore
from updater.version import compare_versions


def update(pkg_dir: Path) -> None:
    """Refresh the immutable source and real Bun dependency hash atomically."""
    hashes_file = pkg_dir / "hashes.json"
    original = load_hashes(hashes_file)
    commit = fetch_json("https://api.github.com/repos/smdex/pi-perplexity/commits/main")
    rev = commit.get("sha") if isinstance(commit, dict) else None
    if not isinstance(rev, str) or not re.fullmatch(r"[a-f0-9]{40}", rev):
        msg = "Expected a full published Git commit"
        raise ValueError(msg)
    manifest = fetch_json(
        f"https://raw.githubusercontent.com/smdex/pi-perplexity/{rev}/cli/package.json"
    )
    version = manifest.get("version") if isinstance(manifest, dict) else None
    if not isinstance(version, str) or not re.fullmatch(
        r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version
    ):
        msg = "Expected a safe CLI semantic version"
        raise ValueError(msg)
    if compare_versions(version, original["version"]) < 0:
        msg = "Refusing a CLI version downgrade"
        raise ValueError(msg)
    print(f"CLI {version}, published source {rev}")
    if (version, rev) == (original["version"], original["rev"]):
        return
    source_hash = calculate_url_hash(
        f"https://github.com/smdex/pi-perplexity/archive/{rev}.tar.gz", unpack=True
    )
    data = dict(original, version=version, rev=rev, hash=source_hash)
    try:
        save_hashes(hashes_file, data)
        DepHasher(
            HashesJsonStore(hashes_file, data=data), ".#pi-perplexity.bunDeps"
        ).hash("bunDepsHash")
    except BaseException:
        save_hashes(hashes_file, original)
        raise


if __name__ == "__main__":
    update(Path(__file__).resolve().parent)
