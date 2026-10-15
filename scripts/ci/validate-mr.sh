#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#bash nixpkgs#git nixpkgs#python3 --command bash
# shellcheck shell=bash
# Validate a fork update MR: the checks a bot MR must pass before the
# guarded merger will merge it.
#
# Runs (mirroring the GitHub PR checks plus a targeted build):
#   1. treefmt formatting/lint gate (--fail-on-change); a full
#      `nix flake check` is deliberately NOT run — it is currently
#      blocked by an unrelated insecure electron dependency.
#   2. maintainers check for newly added packages (reuses
#      .github/ci/check_maintainers.py) — only when packages/** changed.
#   3. README regeneration check (reuses scripts/generate-package-docs.nu)
#      — only when packages/** or the generator changed.
#   4. targeted package build: for update/<package> branches, build the
#      updated package from the MR's source branch.
#
# Environment (set by .gitlab-ci.yml / .woodpecker/validate-mr.yaml):
#   MR_SOURCE_BRANCH  update/<package> branch (auto-detected from
#                     CI_MERGE_REQUEST_SOURCE_BRANCH_NAME /
#                     CI_COMMIT_SOURCE_BRANCH / CI_SOURCE_BRANCH)
#   MR_TARGET_BRANCH  base branch (default: main)

set -euo pipefail

default_branch="${DEFAULT_BRANCH:-main}"
target_branch="${MR_TARGET_BRANCH:-${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-${CI_COMMIT_TARGET_BRANCH:-${CI_TARGET_BRANCH:-$default_branch}}}}"
source_branch="${MR_SOURCE_BRANCH:-${CI_MERGE_REQUEST_SOURCE_BRANCH_NAME:-${CI_COMMIT_SOURCE_BRANCH:-${CI_SOURCE_BRANCH:-}}}}"

echo "== validate-mr: source=${source_branch:-<detached>} target=${target_branch}"

if ! git rev-parse --verify --quiet "origin/${target_branch}" >/dev/null; then
  git fetch origin "${target_branch}"
fi

echo "== treefmt (formatting + lints)"
nix develop --accept-flake-config -c treefmt --fail-on-change

base="origin/${target_branch}"
changed() {
  # Two-dot on purpose: it also covers a dirty work tree, and a false
  # positive merely runs a check that was skippable — a false negative
  # would skip a required one.
  git diff --name-only "$base" -- "$1" | grep -q .
}

if changed 'packages/' || changed 'lib/' || changed '.github/ci/check_maintainers.py'; then
  echo "== maintainers check"
  python3 .github/ci/check_maintainers.py --base-ref "$base"
fi

if changed 'packages/' || changed 'scripts/generate-package-docs.nu' ||
  changed 'scripts/generate-package-docs.nix' || changed 'README.md'; then
  echo "== README regeneration check"
  ./scripts/generate-package-docs.nu
  git diff --exit-code -- README.md
fi

case "${source_branch:-}" in
update/*)
  package="${source_branch#update/}"
  echo "== targeted build: ${package}"
  nix build --accept-flake-config --no-link ".#${package}"
  ;;
*)
  echo "== targeted build skipped (not an update/<package> branch)"
  ;;
esac

echo "== validate-mr: all checks passed"
