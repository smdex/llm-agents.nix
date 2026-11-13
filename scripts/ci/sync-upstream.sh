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
#   SYNC_BRANCH       main (default) or chiki
#   maintenance/chiki-base on origin records the main commit used by chiki;
#                     bootstrap it manually to the verified old main commit
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
sync_branch="${SYNC_BRANCH:-main}"
if [[ $sync_branch != main && $sync_branch != chiki ]]; then
  echo "ERROR: SYNC_BRANCH must be main or chiki" >&2
  exit 1
fi
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
  set +x
  local base="${GL_PROJECT_URL:?GL_PROJECT_URL is required for pushing}"
  base="${base%/}"
  local push_url="${base%.git}.git" auth
  auth="$(printf 'oauth2:%s' "${GL_TOKEN:?GL_TOKEN is required for pushing}" | base64 | tr -d '\n')"
  local -a push_args=(--force-with-lease="refs/heads/${target_branch}:${base_sha}")
  local -a refspecs=("HEAD:refs/heads/${target_branch}")
  if [[ $sync_branch == chiki ]]; then
    push_args+=(--atomic --force-with-lease="refs/heads/maintenance/chiki-base:${marker_sha}")
    refspecs+=("${upstream_sha}:refs/heads/maintenance/chiki-base")
  fi
  GIT_CONFIG_COUNT=5 \
    GIT_CONFIG_KEY_0=http.extraHeader GIT_CONFIG_VALUE_0='' \
    GIT_CONFIG_KEY_1="http.${push_url}.extraHeader" GIT_CONFIG_VALUE_1='' \
    GIT_CONFIG_KEY_2="http.${push_url}.extraHeader" GIT_CONFIG_VALUE_2="Authorization: Basic ${auth}" \
    GIT_CONFIG_KEY_3=credential.helper GIT_CONFIG_VALUE_3='' \
    GIT_CONFIG_KEY_4="credential.${push_url}.helper" GIT_CONFIG_VALUE_4='' \
    GIT_TRACE=0 GIT_TRACE_CURL=0 GIT_CURL_VERBOSE=0 GIT_TRACE_REDACT=1 \
    git push "${push_args[@]}" "$push_url" "${refspecs[@]}"
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
  local target_branch="$default_branch"
  if [[ $sync_branch == chiki ]]; then
    target_branch=chiki
    # Fetch the marker explicitly: a missing remote ref must never reuse a stale local ref.
    git fetch origin "+refs/heads/${default_branch}:refs/remotes/origin/${default_branch}" "+refs/heads/chiki:refs/remotes/origin/chiki" "+refs/heads/maintenance/chiki-base:refs/remotes/origin/maintenance/chiki-base"
    git checkout -B chiki origin/chiki
    local base_sha fork_base marker_sha upstream upstream_sha
    base_sha="$(git rev-parse origin/chiki)"
    fork_base="$(git rev-parse 'origin/maintenance/chiki-base^{commit}')"
    marker_sha="$fork_base"
    upstream_sha="$(git rev-parse "origin/${default_branch}^{commit}")"
    upstream="$upstream_sha"
    if ! git merge-base --is-ancestor "$fork_base" HEAD; then
      echo "ERROR: maintenance/chiki-base is not an ancestor of chiki" >&2
      return 1
    fi
    if [[ $upstream_sha != "$fork_base" ]] && git merge-base --is-ancestor "$upstream_sha" "$fork_base"; then
      echo "ERROR: origin/${default_branch} is older than maintenance/chiki-base" >&2
      return 1
    fi
    # A manually bootstrapped marker may name an upstream commit rather than
    # the fork main already shared by both branches. Do not replay that shared
    # infrastructure. For rewritten main, keep the durable marker as before.
    local common_base
    common_base="$(git merge-base "$upstream" HEAD)"
    if git merge-base --is-ancestor "$fork_base" "$common_base"; then
      fork_base="$common_base"
    fi
    if git merge-base --is-ancestor "$upstream" HEAD; then
      push_result
      echo "chiki already contains origin/${default_branch}"
      return 0
    fi
    rebase_branch
    return
  fi
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

  rebase_branch
}

rebase_branch() {
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
  echo "Rebased ${target_branch} onto ${upstream}."
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
        local side=--ours
        if [[ $sync_branch == chiki && $path == packages/* ]]; then
          side=--theirs
        fi
        if git checkout "$side" -- "$path"; then
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
