#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""The legacy TUI frontend and its private ACP backend are manually pinned."""

print("goose-tui is manually pinned; review its frontend and goose2/cli.nix together")
