#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Update autolith and re-vendor its upstream nix/package.nix."""

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent.parent / "scripts"))

from updater import (
    calculate_url_hash,
    fetch_github_latest_release,
    fetch_text,
    should_update,
)
from updater.nix import run_command

PACKAGE_DIR = Path(__file__).parent
HASHES = PACKAGE_DIR / "hashes.json"
UPSTREAM_NIX = PACKAGE_DIR / "upstream-package.nix"
OWNER = "lambda-symbolics"
REPO = "autolith"


def vendor_upstream_nix(tag: str) -> str:
    """Fetch upstream's package.nix and strip the parts that need IFD.

    Inline release metadata rather than reading a derivation during evaluation.
    Drop upstream's SBCL version/hash pin to follow nixpkgs' SBCL.
    """
    base = f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{tag}"
    text = fetch_text(f"{base}/nix/package.nix")
    fff_commit = fetch_text(f"{base}/native/fff/commit").strip()
    version_read = 'lib.removeSuffix "\\n" (builtins.readFile "${src}/VERSION")'
    if version_read in text:
        version = fetch_text(f"{base}/VERSION").strip()
        if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version):
            msg = "invalid upstream VERSION metadata"
            raise ValueError(msg)
        text = text.replace(version_read, json.dumps(version))
    if 'qlotLock = builtins.readFile "${src}/qlfile.lock";' in text:
        lock = (
            fetch_text(f"{base}/qlfile.lock").replace("''", "'''").replace("${", "''${")
        )
        text = text.replace(
            'qlotLock = builtins.readFile "${src}/qlfile.lock";',
            "qlotLock = ''\n" + lock + "\n'';",
        )

    text = re.sub(
        r"^  fffSourceCommit = .*$",
        f'  fffSourceCommit = "{fff_commit}";',
        text,
        count=1,
        flags=re.MULTILINE,
    )
    # sbclSource: drop the hash comparison block, keep the extraction.
    text = re.sub(
        r"\n    actual_hash=.*?\n    fi\n", "\n", text, count=1, flags=re.DOTALL
    )
    text = re.sub(
        r"^.*expectedSbcl(Version|SourceHash) = .*\n", "", text, flags=re.MULTILINE
    )
    text = re.sub(
        r"^assert pkgs\.sbcl\.version == expectedSbclVersion;\n",
        "",
        text,
        flags=re.MULTILINE,
    )
    text = text.replace("${expectedSbclVersion}", "${pkgs.sbcl.version}")
    text = re.sub(r"\bstdenv\.is(Linux|Darwin)\b", r"stdenv.hostPlatform.is\1", text)
    if "expectedSbcl" in text:
        msg = "upstream package.nix changed shape; adjust vendor_upstream_nix()"
        raise ValueError(msg)
    return text


def main() -> None:
    """Update to the latest tagged release."""
    data = json.loads(HASHES.read_text())
    current = data["version"]
    latest = fetch_github_latest_release(OWNER, REPO)
    print(f"Current: {current}, Latest: {latest}")
    if not should_update(current, latest):
        print("Already up to date")
        return

    tag = f"v{latest}"
    upstream = vendor_upstream_nix(tag)
    src_hash = calculate_url_hash(
        f"https://github.com/{OWNER}/{REPO}/archive/refs/tags/{tag}.tar.gz",
        unpack=True,
    )
    crane = json.loads(
        fetch_text(f"https://raw.githubusercontent.com/{OWNER}/{REPO}/{tag}/flake.lock")
    )["nodes"]["crane"]["locked"]
    if crane["type"] != "github":
        msg = "upstream Crane input is no longer a pinned GitHub source"
        raise ValueError(msg)
    UPSTREAM_NIX.write_text(upstream)
    HASHES.write_text(
        json.dumps({"version": latest, "hash": src_hash, "crane": crane}, indent=2)
        + "\n"
    )
    # Keep the vendored file in treefmt's style so updates show real diffs only.
    run_command(["nix", "fmt", "--", str(UPSTREAM_NIX)], cwd=PACKAGE_DIR.parent.parent)
    print(f"Updated to {latest}")


if __name__ == "__main__":
    main()
