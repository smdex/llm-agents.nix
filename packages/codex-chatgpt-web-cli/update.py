#!/usr/bin/env python3

"""No-op update checker for codex-chatgpt-web-cli.

The CLI is version-locked to codex-chatgpt-web: it shares
packages/codex-chatgpt-web/hashes.json and bun.nix and asserts version
equality with the desktop package at eval time. Bump it by running the main
package's update.py (packages/codex-chatgpt-web/update.py), which updates
hashes, both lockfile trees, and thereby this package in one go. This script
exists only so CI's companion sweep finds a runnable updater in this
directory; it intentionally imports nothing beyond the stdlib.
"""

from pathlib import Path

LOCKED_TO = Path(__file__).parent.parent / "codex-chatgpt-web"


def main() -> None:
    """Confirm the wiring and exit successfully without changing anything."""
    print(
        "codex-chatgpt-web-cli is version-locked to codex-chatgpt-web "
        f"({LOCKED_TO}/hashes.json); nothing to update here. "
        "Run packages/codex-chatgpt-web/update.py to bump the pair."
    )


if __name__ == "__main__":
    main()
