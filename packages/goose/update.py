#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 --command python3

"""Manual updater for the legacy ``goosed`` source package.

Upstream removed the ``goose-server`` Cargo package after v1.41.0, while the
Electron 1.45 app now launches the source-built ``goose serve`` CLI. Keep this
compatibility package pinned to the last release that actually provides
``goosed``; do not silently replace it with the unrelated ACP executable.
"""

print("goose (goosed) is manually pinned to upstream v1.41.0")
