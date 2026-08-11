#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Manual updater for the Goose 2 source package.

Goose 2 is pinned to a preview tag and is built from its Rust/Tauri source.
Updating it requires one coordinated change to the upstream tag/source hash,
Cargo vendor hash, pnpm dependency hash, builderbot Doctor revision/hash, and
librusty_v8 input. This updater deliberately does not inspect or rewrite Goose
1.x release tags and never refers to application deb artifacts.
"""

print(
    "goose2 is a manually coordinated source update; update the pinned Goose 2 "
    "tag and all source dependency hashes together"
)
