# GitLab + Woodpecker fork maintenance CI

This fork runs its maintenance flow — **sync upstream → update fork-only
packages → merge validated update MRs** — on a **GitLab-hosted** copy of
the repository, with [Woodpecker CI] attached to that GitLab instance via
the **GitLab forge**. This document is the contract between those two
systems; the GitHub workflows in `.github/workflows/` (upstream-owned,
never modified by the fork) remain the reference implementation.

## Assumptions

1. **The repository is hosted on GitLab** (self-managed or gitlab.com) as
   a fork/mirror of `github:numtide/llm-agents.nix`, with the default
   branch `main` (the upstream updater stack assumes `origin/main`).
1. **Woodpecker CI uses the GitLab forge**: the repo is enabled in
   Woodpecker, Woodpecker clones over the GitLab API, and reports commit
   statuses named `ci/woodpecker/...` back to GitLab. Woodpecker does
   *not* need push access of its own; pushes use the `GL_TOKEN` secret.
1. Either system can drive the maintenance chain, but **enable the
   schedule in exactly one of them** (GitLab pipeline schedule *or*
   Woodpecker cron). The chain is idempotent (ancestor fast path,
   guarded merges), but running both just duplicates work.

## Files

| File | Role |
| --- | --- |
| `.gitlab-ci.yml` | GitLab: scheduled maintenance chain + MR validation pipeline |
| `.woodpecker/maintenance.yaml` | Woodpecker: same chain, on `cron`/`manual` events only |
| `.woodpecker/validate-mr.yaml` | Woodpecker: validation pipeline for MRs (`pull_request` event) |
| `scripts/ci/fork-packages.sh` | fork-added packages = directory set difference `packages/` vs upstream |
| `scripts/ci/sync-upstream.sh` | rebase `main` onto upstream, regenerate README, force-with-lease push |
| `scripts/ci/update_fork_packages.py` | per-package driver around the unmodified `.github/ci` updater |
| `scripts/ci/gitlab_mr.py` | confinement check, pristine-clone publish, MR create/update, downgrade guard |
| `scripts/ci/merge_update_mrs.py` | guarded merger for bot update MRs |
| `scripts/ci/validate-mr.sh` | MR checks: treefmt gate, maintainers, README regen, targeted build |
| `checks/ci-tests.nix` | runs `scripts/ci/*_test.py` under `nix flake check` |

Every shell/python entry point carries a nix shebang
(`nix shell --inputs-from .# …`), so any runner image that ships `nix`
is sufficient — no other tooling is preinstalled by the jobs.

## Setup

1. **Token**: create a GitLab *project access token* with the Maintainer
   role and `api` scope (push + MR create/merge). The merger resolves
   the bot identity from the token itself (`GET /user`), so MR author
   checks always match.
   - GitLab: add it as a **masked + protected** CI/CD variable `GL_TOKEN`.
     *Protected* is what keeps it away from MR pipelines — combined with
     the `workflow: rules` (schedule/web/merge_request only) the token is
     only ever visible to maintenance jobs on the protected `main`.
     Keep `update/*` unprotected and do not enable protected-variable access
     for MR pipelines. In Woodpecker, restrict the secret to cron/manual
     events, never pull requests.
   - Woodpecker: add it as a repository **secret** named `GL_TOKEN`, and
     only the `maintenance.yaml` steps declare it.
1. **GitLab**: protect `main`, allow the project bot to push/merge, and
   enable **Allow force push** for `main` (required for the leased rebase
   push). Limit direct pushes to trusted maintainers/the bot. Enable runners with a nix-capable image
   (`nixos/nix` is the default in `.gitlab-ci.yml`), and add a pipeline
   schedule on `main` (e.g. every 30 minutes — no-op runs are cheap).
1. **Woodpecker** (if it drives the chain): add a cron for
   `maintenance.yaml` on `main`. `validate-mr.yaml` needs no secrets.
   Allow at least two concurrent pipelines so waiting maintenance does not
   block MR validation. Serialize scheduled maintenance runs (do not start
   a second manual maintenance run while one is active).

## The chain

### 1. Sync upstream (`sync-upstream.sh`)

Port of `.github/workflows/sync-upstream.yml`:

- best-effort gate: skip while upstream's own `update.yml` workflow is
  mid-run (unreachable API = not blocked);
- fast path when `upstream/main` is already an ancestor;
- `git rebase -i --onto upstream/main --empty=drop` with the
  `sync: regenerate README` commits dropped from the todo;
- conflicts are auto-resolved only for `README.md` and `packages/*`
  (upstream side wins during the rebase); anything else aborts;
- the result must be linear (`--ff`-able stack of fork commits, no merge
  commits) before anything is pushed;
- README package docs are regenerated (`scripts/generate-package-docs.nu`);
- push with `--force-with-lease=main:<observed remote sha>`, so any
  concurrent change (e.g. a just-merged MR) refuses the push instead of
  being clobbered.

### 2. Update fork-only packages (`update_fork_packages.py`)

**Fork-only packages are the directory set difference** of `packages/` on
`main` minus `packages/` on `upstream/main` (`fork-packages.sh`) — *not*
a git-history diff, so upstream packages modified by the fork are not
touched. `FORK_UPDATE_PACKAGES` can select a subset of that list; shared
upstream or nonexistent package names are rejected.

For each package, reusing the upstream CI scripts unmodified:

1. `.github/ci/discovery.py` builds the matrix (versions, hidden
   packages, companions).
1. The `update/<package>` branch is reused/rebased onto `main` (manual
   fixups on open MRs carry over), with a hard reset + clean before each
   package so no state leaks between iterations.
1. `.github/ci/update.py package <name>` runs from a **stashed copy** of
   the CI scripts, inside the devshell (for `nix-update` et al.) wrapped
   with `nix shell nixpkgs#python3`, and with **credential variables removed
   from its environment** (`GL_TOKEN`, `CI_JOB_TOKEN`, `GITHUB_TOKEN`,
   `GH_TOKEN`, clone URLs, and variables named with TOKEN/PASSWORD/SECRET/
   PRIVATE_KEY) plus git hooks/fsmonitor disabled. Trusted git operations
   authenticate with environment-only headers, not token-bearing URLs or argv.
   Companions that belong to upstream are rejected before any updater runs.
1. A **downgrade guard** (`is_downgrade`) refuses to publish version
   regressions (set `ALLOW_DOWNGRADE=1` to override) — the fork updater
   stack has no built-in protection against them.
1. `gitlab_mr.py` publishes: confinement check (only
   `packages/<name>/` and its `update-companions` may differ from
   `main`), then a pristine shallow clone (never the updater's checkout)
   is force-pushed, and the MR is created/updated with the labels
   `dependencies,automated`.

Exit codes: `0` clean, `1` some packages failed (others still publish;
the merge stage still runs — job uses `allow_failure: [1]`), `2`
systemic failure.

### 3. Merge validated update MRs (`merge_update_mrs.py`)

Replaces `auto-merge.yml`. Polls open MRs and merges one only when **all**
of the following hold:

- author is the token's bot user, source branch is `update/<package>`,
  target is the default branch in the same project, labels `dependencies`
  and `automated` present, not draft/WIP;
- validation is green for the MR's **head SHA**: the GitLab
  `head_pipeline` succeeded (with `pipeline.sha == mr.sha` and source
  `merge_request_event`, not an external-status-only pipeline) **and/or**
  every `ci/woodpecker/...` commit status for that SHA succeeded, including
  `ci/woodpecker/pr/validate-mr`. If your server customizes status names,
  set `WOODPECKER_VALIDATION_CONTEXT` to its exact MR-validation context; at
  least one source of evidence must exist — otherwise the MR waits;
- GitLab reports the MR mergeable;
- the MR is re-fetched immediately before merging and the merge call
  pins that SHA server-side (`sha` parameter), so any push between check
  and merge aborts the merge (HTTP 400/405/406/409 are retried until
  `MERGE_WAIT_TIMEOUT`, default 1800 s, not treated as job failures).

**Human or arbitrary pending MRs are never merged** — they fail
eligibility on author/branch/label before any validation is inspected.

### MR validation (`validate-mr.sh`)

Runs on `merge_request_event` (GitLab) and `pull_request` (Woodpecker):

- treefmt gate (`--fail-on-change`; a full `nix flake check` is
  deliberately not run — currently blocked by an unrelated insecure
  electron dependency),
- maintainers check for new packages (`.github/ci/check_maintainers.py`,
  path-filtered),
- README regeneration check (path-filtered),
- targeted `nix build .#<package>` for `update/<package>` branches.

## Local testing

```console
$ cd scripts && python3 -m unittest discover -s ci -p '*_test.py' -t . -v   # unit tests
$ nix build .#checks.x86_64-linux.ci-tests                                  # same, hermetic
$ nix fmt                                                                  # formatters + shellcheck + ruff
```

## Limitations

- Credential environment filtering and pristine publishing are not an OS
  isolation boundary against hostile package code. Run only trusted fork
  updaters on dedicated ephemeral runners; bubblewrap can be unavailable
  in containers and the reused updater falls back to unsandboxed execution.
  Do not run adversarial updater code alongside push credentials.
- Not exercised against a live GitLab/Woodpecker instance here; API
  interactions are covered by unit tests with fake transports only.
- The maintenance jobs are sequential per package (no matrix fan-out as
  on GitHub); a package with a slow updater delays the rest.
- `update_fork_packages.py` hardcodes `main` as the base branch because
  the reused upstream `update.py` diffs against `origin/main`.

## Validation evidence

The workflow YAML passes `woodpecker-cli 3.18.0 lint`. Default status
context naming is grounded in Woodpecker v3.18.0
[`cmd/server/flags.go`](https://github.com/woodpecker-ci/woodpecker/blob/v3.18.0/cmd/server/flags.go)
(`ci/woodpecker/<event>/<workflow>`, pull requests use `pr`). Confirm the
exact context on your instance before enabling merging. GitLab commit
status parsing follows the REST
[`name` / `status` response fields](https://docs.gitlab.com/api/commits/#list-commit-statuses),
not the `context` / `state` names used when posting a status.

[woodpecker ci]: https://woodpecker-ci.org
