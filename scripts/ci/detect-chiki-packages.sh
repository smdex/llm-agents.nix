#!/usr/bin/env bash
set -euo pipefail

changed=$(git diff --no-renames --name-only origin/main...origin/chiki -- packages/)
while IFS= read -r path; do
  [[ $path == packages/*/* ]] || continue
  package=${path#packages/}
  package=${package%%/*}
  if [[ $(git cat-file -t "origin/chiki:packages/$package" 2>/dev/null || true) == tree ]]; then
    printf '%s\n' "$package"
  fi
done <<<"$changed" | LC_ALL=C sort -u
