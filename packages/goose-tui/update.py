#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Goose TUI follows the legacy Goose 1.x source release used by goose-cli."""

print("goose-tui is locked to goose-cli; run packages/goose-cli/update.py")
