#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#bash nixpkgs#git nixpkgs#curl nixpkgs#jq nixpkgs#gnused nixpkgs#coreutils --command bash
# shellcheck shell=bash
# Rebase the fork's default branch onto upstream/main and push it.
#
# Port of .github/workflows/sync-upstream.yml (kept unmodified,
# upstream-owned): ancestor fast path, replay of fork commits with the
# "sync: regenerate README" commits dropped from the todo, automatic
# conflict resolution for package files and README.md (upstream side
# wins during the rebase; README is regenerated afterwards), linearity
# checks, README regeneration, and a force-with-lease push anchored on
# the remote head observed by this checkout.
#
# Environment:
#   UPSTREAM_URL      default https://github.com/numtide/llm-agents.nix.git
#   UPSTREAM_REF      default main
#   DEFAULT_BRANCH    default main (must match the repo's default branch;
#                     the upstream updater stack assumes origin/main)
#   GL_PROJECT_URL    full https URL of the GitLab project (token is
#                     appended for the push; never logged)
#   GL_TOKEN          GitLab token allowed to push the default branch
#   UPSTREAM_UPDATE_WORKFLOW  upstream workflow file to wait for
#                     (default update.yml); the gate is best-effort and
#                     skipped when the GitHub API is unreachable.
#
# Exit codes: 0 = pushed or already up to date; 1 = failure (default
# branch left unchanged unless the push itself failed).

set -euo pipefail

default_branch="${DEFAULT_BRANCH:-main}"
upstream_url="${UPSTREAM_URL:-https://github.com/numtide/llm-agents.nix.git}"
upstream_repo="${UPSTREAM_REPOSITORY:-numtide/llm-agents.nix}"
upstream_ref="${UPSTREAM_REF:-main}"
upstream_workflow="${UPSTREAM_UPDATE_WORKFLOW:-update.yml}"

git_identity() {
  git config user.name "${CI_BOT_NAME:-llm-agents-bot}"
  git config user.email "${CI_BOT_EMAIL:-llm-agents-bot@users.noreply.gitlab.local}"
}

push_result() {
  # Keep the push token out of argv, git config, and logs.
  local base="${GL_PROJECT_URL:?GL_PROJECT_URL is required for pushing}"
  local auth
  auth="$(printf 'oauth2:%s' "${GL_TOKEN:?GL_TOKEN is required for pushing}" | base64 | tr -d '\n')"
  GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="http.${base%/}.extraHeader" \
    GIT_CONFIG_VALUE_0="Authorization: Basic ${auth}" \
    git push --force-with-lease="${default_branch}:${base_sha}" "${base%.git}.git" "HEAD:${default_branch}"
}

upstream_update_in_progress() {
  # Best-effort gate (parity with sync-upstream.yml): do not rebase
  # while the upstream's own update workflow is mid-run. Any API
  # failure means "not blocked" — same as the GitHub catch branch.
  local url="https://api.github.com/repos/${upstream_repo}/actions/workflows/${upstream_workflow}/runs?branch=${upstream_ref}&per_page=1"
  local body
  if ! body=$(curl -fsS --max-time 20 "$url"); then
    echo "upstream workflow check skipped (GitHub API unreachable)" >&2
    return 1
  fi
  local status
  status=$(jq -r '.workflow_runs[0].status // "none"' <<<"$body")
  [[ $status == "in_progress" || $status == "queued" ]]
}

main() {
  git_identity
  # Jobs may start from the old pipeline SHA after an earlier sync/merge.
  git fetch origin "+refs/heads/${default_branch}:refs/remotes/origin/${default_branch}"
  git checkout -B "$default_branch" "origin/${default_branch}"

  if upstream_update_in_progress; then
    echo "Upstream ${upstream_workflow} workflow is running; skipping this sync."
    exit 0
  fi

  if ! git remote get-url upstream >/dev/null 2>&1; then
    git remote add upstream "$upstream_url"
  fi
  git fetch upstream "+refs/heads/${upstream_ref}:refs/remotes/upstream/${upstream_ref}"
  local upstream="upstream/${upstream_ref}"

  if git merge-base --is-ancestor "$upstream" HEAD; then
    echo "${default_branch} already contains ${upstream}"
    exit 0
  fi

  # Lease anchor: the remote default branch as seen by this checkout.
  # Pushing with an explicit expected SHA refuses to move the branch if
  # anything (e.g. an auto-merged MR) advanced it since.
  local base_sha
  base_sha="$(git rev-parse "origin/${default_branch}")"
  local fork_base
  fork_base="$(git merge-base "$upstream" HEAD)"

  export GIT_EDITOR=true
  # Replay only real fork commits: previous syncs leave "sync:
  # regenerate README" commits behind, so drop them from the todo and
  # rebuild the generated section once below. Interactive mode (-i) is
  # what makes git honor GIT_SEQUENCE_EDITOR.
  export GIT_SEQUENCE_EDITOR="sed -i '/^pick .*sync: regenerate README after upstream rebase$/d'"

  if ! git rebase -i --onto "$upstream" --empty=drop "$fork_base"; then
    resolve_rebase_conflicts || {
      git rebase --abort 2>/dev/null || true
      echo "ERROR: upstream rebase could not be resolved" >&2
      exit 1
    }
  fi

  # The result must be a linear stack of fork-only commits on top of
  # the upstream ref just fetched; refuse to push anything else.
  if ! git merge-base --is-ancestor "$upstream" HEAD; then
    echo "ERROR: rebase result does not contain ${upstream}; refusing to push" >&2
    exit 1
  fi
  if [[ -n "$(git rev-list --merges HEAD --not "$upstream")" ]]; then
    echo "ERROR: rebase result contains merge commits; refusing to push" >&2
    exit 1
  fi

  # Regenerate the package-docs section so it includes both upstream
  # and fork packages after the rebase.
  ./scripts/generate-package-docs.nu
  git add README.md
  if ! git diff --cached --quiet -- README.md; then
    git commit -m "sync: regenerate README after upstream rebase"
  fi

  push_result
  echo "Rebased ${default_branch} onto ${upstream}."
}

resolve_rebase_conflicts() {
  # Only enter the loop if a rebase is actually in progress.
  if ! test -d .git/rebase-merge && ! test -d .git/rebase-apply; then
    echo "ERROR: upstream rebase failed before reporting a conflict" >&2
    return 1
  fi

  while test -d .git/rebase-merge || test -d .git/rebase-apply; do
    local conflicts
    conflicts="$(git diff --name-only --diff-filter=U)"
    if [[ -z $conflicts ]]; then
      echo "ERROR: rebase stopped without reporting conflicted files" >&2
      return 1
    fi

    while IFS= read -r path; do
      case "$path" in
      README.md | packages/*)
        # During a rebase, --ours is upstream. Package files
        # already present upstream are authoritative; README is
        # generated again after the rebase.
        if git checkout --ours -- "$path"; then
          git add -- "$path"
        else
          # Also handle modify/delete conflicts where upstream
          # removed the package.
          git rm -- "$path"
        fi
        ;;
      *)
        echo "ERROR: upstream rebase has an unexpected conflict: $path" >&2
        return 1
        ;;
      esac
    done <<<"$conflicts"

    if git rebase --continue; then
      break
    fi
  done

  if test -d .git/rebase-merge || test -d .git/rebase-apply; then
    echo "ERROR: rebase did not finish after resolving generated/package conflicts" >&2
    return 1
  fi
}

main "$@"
