#!/usr/bin/env python3
"""No-op updater for goose2.

The Goose 2 desktop package follows preview release assets whose release tag and
embedded package version do not move together. nix-update sees the latest Goose
1.x release, rewrites version to that value, and then fetches a non-existent
Goose_${version}_amd64.deb from the fixed Goose 2 preview tag.

Keep this package manual until upstream publishes updateable Goose 2 releases.
"""

print("goose2 is managed manually; skipping automatic update")
