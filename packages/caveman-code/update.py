#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#nodejs --command python3

"""Update script for caveman-code package.

caveman-code is a buildNpmPackage whose src is the published npm tarball
(fetched via fetchurl) and whose package-lock.json is vendored in-tree
because the tarball ships none. Version, src hash and npmDepsHash all live
inline in package.nix (no hashes.json), so this updater edits them directly
rather than going through the hashes-file helpers.
"""

import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import calculate_url_hash, should_update  # noqa: E402
from updater.hash import DUMMY_SHA256_HASH, extract_hash_from_build_error  # noqa: E402
from updater.nix import NixCommandError, nix_build  # noqa: E402
from updater.npm import extract_or_generate_lockfile  # noqa: E402
from updater.version import fetch_npm_version  # noqa: E402

PKG_DIR = Path(__file__).parent
PACKAGE_NIX = PKG_DIR / "package.nix"
LOCKFILE = PKG_DIR / "package-lock.json"

NPM_PACKAGE = "@juliusbrussee/caveman-code"
FLAKE_ATTR = ".#caveman-code"


def current_version() -> str:
    """Read the inline version string from package.nix."""
    match = re.search(r'\bversion\s*=\s*"([^"]+)"', PACKAGE_NIX.read_text())
    if not match:
        msg = "could not find version in package.nix"
        raise ValueError(msg)
    return match.group(1)


def set_inline_attr(attr: str, value: str) -> None:
    """Replace the first inline `<attr> = "..."` assignment in package.nix."""
    pattern = re.compile(rf'(\b{re.escape(attr)}\s*=\s*")[^"]*(")')

    def repl(match: re.Match[str]) -> str:
        return f"{match.group(1)}{value}{match.group(2)}"

    content = PACKAGE_NIX.read_text()
    new_content, count = pattern.subn(repl, content, count=1)
    if count != 1:
        msg = f"could not replace inline attribute {attr!r} in package.nix"
        raise ValueError(msg)
    PACKAGE_NIX.write_text(new_content)


def set_npm_deps_hash(value: str) -> None:
    """Convenience wrapper for the npmDepsHash attribute."""
    set_inline_attr("npmDepsHash", value)


def tarball_url(version: str) -> str:
    """Build the npm registry tarball URL for a given version."""
    tarball_name = NPM_PACKAGE.rsplit("/", 1)[-1]
    return f"https://registry.npmjs.org/{NPM_PACKAGE}/-/{tarball_name}-{version}.tgz"


def calculate_npm_deps_hash() -> str:
    """Compute npmDepsHash via the dummy-and-build pattern.

    Writes the dummy hash inline, runs `nix build` (expected to fail on the
    fixed-output deps FOD), and extracts the real hash from the error.
    Restores the previous value on failure so CI never commits a placeholder.
    """
    original_match = re.search(
        r'\bnpmDepsHash\s*=\s*"([^"]+)"', PACKAGE_NIX.read_text()
    )
    if not original_match:
        msg = "could not find current npmDepsHash in package.nix"
        raise ValueError(msg)
    original = original_match.group(1)

    set_npm_deps_hash(DUMMY_SHA256_HASH)

    try:
        nix_build(FLAKE_ATTR, check=True)
    except NixCommandError as e:
        dep_hash = extract_hash_from_build_error(e.args[0])
        if not dep_hash:
            set_npm_deps_hash(original)
            msg = f"could not extract npmDepsHash from build error:\n{e.args[0]}"
            raise ValueError(msg) from e
        return dep_hash

    set_npm_deps_hash(original)
    msg = "build succeeded with dummy npmDepsHash - unexpected"
    raise ValueError(msg)


def main() -> None:
    """Update the caveman-code package."""
    current = current_version()
    latest = fetch_npm_version(NPM_PACKAGE)

    print(f"Current: {current}, Latest: {latest}")

    if not should_update(current, latest):
        print("Already up to date")
        return

    print(f"Updating caveman-code from {current} to {latest}")

    url = tarball_url(latest)

    if not extract_or_generate_lockfile(url, LOCKFILE):
        msg = "failed to regenerate package-lock.json"
        raise SystemExit(msg)

    print("Calculating source hash...")
    source_hash = calculate_url_hash(url)
    set_inline_attr("hash", source_hash)
    set_inline_attr("version", latest)

    print("Calculating npm dependencies hash...")
    set_npm_deps_hash(calculate_npm_deps_hash())

    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
