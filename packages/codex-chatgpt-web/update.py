#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update script for the codex-chatgpt-web package pair.

The desktop GUI (codex-chatgpt-web) and its CLI companion
(codex-chatgpt-web-cli) share one upstream source tree, one hashes.json and
one root bun.nix — all in this directory. This updater moves both at once:

  1. bump version + src hash in hashes.json,
  2. regenerate bun.nix (root) from the tag's bun.lock,
  3. regenerate bun-launcher.nix (launcher/) from the tag's launcher/bun.lock.

The CLI package reads the same hashes.json/bun.nix via relative paths and
asserts version equality with the desktop at eval time; its own update.py is
a no-op checker that only confirms this wiring.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    clone_and_generate_bun_nix,
    fetch_github_latest_release,
    load_hashes,
    regenerate_bun_nix,
    save_hashes,
    should_update,
)

OWNER = "miuuyy"
REPO = "codex-chatgpt-web"

HASHES_FILE = Path(__file__).parent / "hashes.json"
PKG_DIR = Path(__file__).parent
FLAKE_ROOT = PKG_DIR.parent.parent


def regenerate_launcher_bun_nix(version: str) -> None:
    """Regenerate bun-launcher.nix from the tag's launcher/bun.lock.

    The launcher lockfile legitimately contains devDependencies (vite,
    electron) — the renderer build needs them — so a plain
    ``--lockfile-only`` refresh (devDeps included) is used when the shipped
    lock is missing.
    """
    with tempfile.TemporaryDirectory() as tmpdir:
        clone = Path(tmpdir) / REPO

        print(f"Cloning {OWNER}/{REPO} at v{version} (launcher)...")
        subprocess.run(
            [
                "git",
                "clone",
                "--depth=1",
                f"--branch=v{version}",
                f"https://github.com/{OWNER}/{REPO}.git",
                str(clone),
            ],
            check=True,
            capture_output=True,
        )

        launcher_lock = clone / "launcher" / "bun.lock"
        if not launcher_lock.exists():
            print("No launcher/bun.lock in the tag, generating lockfile...")
            subprocess.run(
                ["bun", "install", "--lockfile-only"],
                cwd=clone / "launcher",
                check=True,
                capture_output=True,
            )

        regenerate_bun_nix(
            launcher_lock,
            PKG_DIR / "bun-launcher.nix",
            FLAKE_ROOT,
        )


def main() -> None:
    """Update the codex-chatgpt-web package pair."""
    data = load_hashes(HASHES_FILE)
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    url = f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/v{latest}.tar.gz"

    print("Calculating source hash...")
    source_hash = calculate_url_hash(url, unpack=True)

    save_hashes(HASHES_FILE, {"version": latest, "hash": source_hash})

    # Root lockfile tree (shared with codex-chatgpt-web-cli). Handles stale
    # upstream lockfiles (writes fix-stale-bun-lock.patch into PKG_DIR).
    clone_and_generate_bun_nix(
        OWNER,
        REPO,
        latest,
        PKG_DIR / "bun.nix",
        FLAKE_ROOT,
        ref_prefix="v",
        pkg_dir=PKG_DIR,
    )

    # Launcher lockfile tree (renderer devDeps included on purpose).
    regenerate_launcher_bun_nix(latest)

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
