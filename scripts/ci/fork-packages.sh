#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#bash nixpkgs#git nixpkgs#gnugrep nixpkgs#gnused nixpkgs#coreutils --command bash
# shellcheck shell=bash
# Fork-added package names for the fork-only update flow.
#
# Distinct packages are the DIRECTORY SET DIFFERENCE of packages/ on the
# fork's default branch minus packages/ on upstream — deliberately not a
# git-history diff: upstream packages modified in this fork are not fork
# additions and stay on the upstream update flow.
#
# Environment:
#   UPSTREAM_URL        upstream repository (default: numtide/llm-agents.nix)
#   UPSTREAM_REF        upstream branch to compare (default: main)
#   FORK_REF            fork ref holding the fork's package set
#                       (default: origin/<DEFAULT_BRANCH or main>)
#   FORK_UPDATE_PACKAGES  optional subset selection (space-separated);
#                       names outside the fork-added set are rejected.
#
# Output: one package name per line. Run "bash scripts/ci/fork-packages.sh"
# to bypass the nix shebang in tests/sandboxes.

set -euo pipefail

default_branch="${DEFAULT_BRANCH:-main}"
fork_ref="${FORK_REF:-origin/${default_branch}}"
upstream_url="${UPSTREAM_URL:-https://github.com/numtide/llm-agents.nix.git}"
upstream_ref="${UPSTREAM_REF:-main}"

if ! git remote get-url upstream >/dev/null 2>&1; then
  git remote add upstream "$upstream_url"
fi
git fetch upstream "+refs/heads/${upstream_ref}:refs/remotes/upstream/${upstream_ref}"

if ! git rev-parse --verify --quiet "${fork_ref}^{commit}" >/dev/null; then
  echo "ERROR: fork ref ${fork_ref} not found; fetch the default branch first" >&2
  exit 1
fi

ls_tree_names() {
  git ls-tree -d --name-only "$1" -- packages/ | sed -e 's|^packages/||' -e 's|/$||'
}

# -13: suppress upstream-only and common entries; what remains exists in
# the fork but not upstream, i.e. the fork-added packages.
distinct="$(comm -13 \
  <(ls_tree_names "upstream/${upstream_ref}" | sort -u) \
  <(ls_tree_names "$fork_ref" | sort -u))"
if [[ -n ${FORK_UPDATE_PACKAGES:-} ]]; then
  # Optional selection can narrow the fork set, never widen it to shared packages.
  for package in $FORK_UPDATE_PACKAGES; do
    if ! grep -Fxq -- "$package" <<<"$distinct"; then
      echo "ERROR: requested package is not a fork addition: $package" >&2
      exit 1
    fi
  done
  # shellcheck disable=SC2086 # deliberate splitting of the selection
  printf '%s\n' $FORK_UPDATE_PACKAGES
elif [[ -n $distinct ]]; then
  printf '%s\n' "$distinct"
fi
