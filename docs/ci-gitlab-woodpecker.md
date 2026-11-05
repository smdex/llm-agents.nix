# GitLab fork maintenance CI

GitLab is the only CI driver for this fork; the former Woodpecker pipelines
are not used. Scheduled or manually started pipelines on the protected default
branch run **main sync → main updates → main merge → chiki rebase → chiki
updates → chiki merge → GitHub mirror**. GitLab merge request pipelines run
validation separately. Plain pushes do not start a pipeline. The pipeline
commit must already contain the chiki-capable scripts.

## Setup

1. Host the fork on GitLab with default branch `main` and an existing `chiki`
   branch. Protect both branches, restrict direct and force pushes to trusted
   maintainers and the appropriate bot, and allow the bot to merge its MRs.
   Protect `maintenance/chiki-base`, `maintenance/github-main`, and
   `maintenance/github-chiki` from other writers; the bots need permission to
   update them, including force pushes where required. Keep update branches
   unprotected and do not enable protected-variable access for MR pipelines.
1. Configure masked, protected GitLab CI/CD variables `GL_TOKEN` and
   `GL_CHIKI_TOKEN`, scoped to the `main-maintenance` and `chiki-maintenance`
   environments respectively. Each project access token needs the necessary
   API, push and merge permissions for its branch and update MRs. The main
   token also updates the GitHub mirror checkpoints; the chiki token updates
   `maintenance/chiki-base`. The merger resolves the bot user from the token
   unless `CI_BOT_USERNAME` overrides it.
1. Configure a masked, protected `GITHUB_MIRROR_TOKEN` scoped to
   `main-maintenance`, with GitHub repository contents read/write permission
   and permission to update the protected `main` and `chiki` refs. The mirror
   destination is fixed to the GitHub repository in `.gitlab-ci.yml` and
   checked by `scripts/ci/mirror_github.py`. Treat GitHub as a follower, not an
   independently writable source. Store credentials only in CI variables;
   never put token values in this document, URLs, commands, or logs. MR
   validation needs none of these maintenance credentials.
1. Set `CI_NIX_IMAGE` to a Nix-capable image. Provision runners tagged
   `usa-docker-nix` for ordinary jobs, including MR validation, and runners
   tagged `usa-docker-ci-control` for the two merge jobs. Control runners must
   also support the configured image and Nix. Give validation independent
   capacity while mergers wait, or the pipeline can deadlock waiting for its
   own MR checks. The shared `fork-maintenance` resource group serializes jobs,
   not whole pipelines: avoid overlapping scheduled and manual maintenance
   pipelines.
1. Bootstrap the protected checkpoints before enabling a schedule. Set
   `maintenance/chiki-base` to the **verified main commit last incorporated in
   chiki**, which must be an ancestor of chiki; do not guess it from a current
   merge base after a rebase. Set `maintenance/github-main` and
   `maintenance/github-chiki` to the respective **verified current GitHub
   branch tips**. Both GitHub branches and all three GitLab checkpoints must
   already exist. If history or ownership is uncertain, stop and investigate
   before creating or changing a checkpoint. Use trusted, authenticated Git
   tooling without embedding credentials in remote URLs.
1. Create a GitLab schedule for `main`. A manual web pipeline on `main` also
   runs maintenance; a web or scheduled pipeline on another branch does not.

## Maintenance chain

### Main sync and updates

`scripts/ci/sync-upstream.sh` fetches upstream `main`, rebases the fork's main
stack when needed, regenerates README package documentation, and pushes with a
lease anchored to the observed remote tip. Only README and package conflicts
are automatically resolved, using upstream's side for main; unexpected
conflicts, a non-linear result, or a stale lease stop the push. Its upstream
GitHub workflow gate is **best effort**: an unreachable API does not block the
sync.

`scripts/ci/fork-packages.sh` discovers fork-only packages by directory set
difference against upstream, not by history. `FORK_UPDATE_PACKAGES` optionally
selects existing package directories explicitly, including shared overrides.
`update_fork_packages.py` reuses upstream discovery and update
scripts, checks companion eligibility, strips credential variables from updater
processes, guards against version downgrades unless `ALLOW_DOWNGRADE=1`, and
publishes confined changes from a pristine clone to `update/<package>` MRs.
Packages are processed sequentially. Exit code 1 means partial package failures
and is allowed by the job so published updates can still be merged; systemic
failures stop the chain.

### Chiki rebase and updates

The chiki sync rebases the stack since `maintenance/chiki-base` onto current
main. The checkpoint must be an ancestor of chiki, and main must not be older
than the checkpoint. Chiki package conflicts prefer chiki's side; README
conflicts use main's side and the README is regenerated. The chiki branch and
checkpoint advance together in an atomic, leased push. A missing or invalid
checkpoint, unexpected conflict, failed ancestry check, or lease failure stops
the operation.

By default `detect-chiki-packages.sh` selects existing package directories
changed between main and chiki; `CHIKI_UPDATE_PACKAGES` overrides that selection.
An empty selection skips updates. Chiki update branches are named
`update-branch/chiki/<package>` and target chiki.

### Guarded merges

`merge_update_mrs.py` considers only same-project, non-draft MRs authored by
the relevant bot, targeting the configured branch, with both `dependencies`
and `automated` labels and the appropriate update branch prefix. It requires
success from the latest GitLab `merge_request_event` pipeline for the MR head
SHA; external status alone is insufficient. It also requires a mergeable
status, re-fetches and rechecks the MR, and pins the head SHA in the merge
request. A moved head or rejected merge is not merged. Pending validation and
transient merge refusals are polled; failed validation is refused. In these
GitLab jobs `MERGE_WAIT_TIMEOUT` is explicitly 1800 seconds. Unresolved or
refused eligible MRs produce exit code 3, allowed as a warning so later jobs
can continue. Other nonzero exit codes, including infrastructure errors, fail
the job and block the chain.

### GitHub mirror

After both merge sweeps complete successfully or with an allowed warning (not
after each individual merge), `mirror_github.py` fetches GitLab `main`,
`chiki`, and both mirror checkpoints, and requires main to be an ancestor of
chiki. It fetches the two GitHub tips and proceeds only if the **pair** equals
either the checkpoint pair or the current GitLab source pair. It re-fetches
GitLab sources and checkpoints before pushing, then updates both GitHub refs
atomically with per-ref force-with-lease; it advances both GitLab checkpoints
atomically with leases afterwards. This also permits recovery when the GitHub
push succeeded but checkpoint advancement failed: rerun after verifying the
state. Missing refs, divergence, changed source/checkpoints, or failed atomic
pushes fail the job rather than overwrite unverified history. Investigate and
reconcile deliberately; never reset checkpoints merely to silence a failure.

## MR validation

`validate-mr.sh` runs on GitLab `merge_request_event` pipelines without
maintenance credentials. It runs treefmt with `--fail-on-change`, conditionally
checks maintainers and README regeneration based on changed paths, and builds
the target package for a valid update branch for the MR target. A full
`nix flake check` is not run by this script. Ensure GitLab's protected-variable
and runner configuration actually preserves this credential boundary.

## Local testing and limitations

```console
$ cd scripts && python3 -m unittest discover -s ci -p '*_test.py' -t . -v
$ nix build .#checks.x86_64-linux.ci-tests
$ nix fmt
```

Credential filtering and pristine publishing are not an OS isolation boundary
against hostile package code. Use trusted updaters on dedicated ephemeral
runners; the reused updater can fall back to unsandboxed execution when
bubblewrap is unavailable. Do not run adversarial updater code alongside push
credentials. Unit tests use fake transports; verify runner permissions, branch
protection and pipeline behavior on the actual GitLab instance before relying
on automation.
