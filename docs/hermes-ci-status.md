# Hermes CI repair status

## Ownership and safety

- Task owner: Jcode in Herdr PLAN, isolated JJ workspace `hermes-ci` at
  `/home/smaximov/src/llm-agents-hermes-ci`.
- Exclusive llm-agents.nix CI writer. The other client `wB:p1P` is not a repair
  writer. The default workspace's conflicted sheprd change is untouched.
- No account permissions, production deployments, destructive resets or force
  pushes are authorized or performed. Only a new CI-fix branch and validation
  retriggers are in scope.

## Live evidence, November 16, 2026 UTC

- Latest maintenance at intake: pipeline
  <https://git.fila.lab/smaximov/llm-agents.nix/-/pipelines/10408>, source
  `schedule`, initial SHA `cb3e3ee546f97bbb04fc82b6f6ac79169e786768`.
- Its sync job 35416 passed. Package-update job 35417 was still running at
  00:55 UTC. Chiki rebase and final GitHub mirror have not yet completed.
  A passed sync job is not proof that GitHub is current.
- Latest failed MR pipeline at intake:
  <https://git.fila.lab/smaximov/llm-agents.nix/-/pipelines/10405>, job
  <https://git.fila.lab/smaximov/llm-agents.nix/-/jobs/35411>, source SHA
  `3b0e81a930cfe83a35398c5bb559aa4f7d7b8115`, MR !35 (`update/vtcode`).
  Formatting, maintainer and README checks passed. The actual vtcode 0.182.4
  build failed: its workspace crates require rustc 1.100.0, but the package's
  custom toolchain is pinned to 1.99.1.

## Parent and branch comparisons

- Repair parent: GitLab main `33e344dd7a25263837cb745f279e4156ca4fc4d2`.
- GitLab chiki snapshot: `fe616807a853986f63afe39ad2455c9bc8021038`.
- GitHub API comparison at 00:55 UTC confirmed the independent audit:
  `numtide:main...smdex:main` has 34 upstream-only and 28 fork-only commits.
  `numtide:main...smdex:chiki` has 34 upstream-only and 39 fork-only commits.
  Both merge bases are `aeb1afe1529c5dc7dcdc54d644a8aed212d99dd0`.
- GitHub main snapshot: `cb3e3ee546f97bbb04fc82b6f6ac79169e786768`.
- After fetching upstream main at 00:58 UTC, its tip is
  `8adf052a0006d9617a7d6c0fe5a628e1eb48a5dc`. Exact Git comparisons:
  `upstream/main...gitlab/main` = 0 upstream-only / 28 fork-only;
  `gitlab/main...gitlab/chiki` = 62 main-only / 39 chiki-only. The latter
  includes rewritten fork commits because chiki has not yet been rebased by
  the running pipeline. No fork commits are discarded by this repair.
- These are GitHub fork comparisons, not evidence that the in-flight GitLab
  sync failed. Exact final GitLab/GitHub tips and ancestry remain to be checked.

## Minimal repair in progress

- `packages/vtcode/rust-toolchain.nix`: pin Rust 1.100.0, released November 12,
  2026\. All three archive hashes are taken from the official versioned Rust
  channel manifest, not guessed from a failed build.
- `packages/vtcode/package.nix`: reproduce MR !35's exact 0.182.4 source and
  cargo hashes so the repaired compiler is tested against the failing update.
- `scripts/ci/validate-mr.sh`: recognize `ci-fix/<package>` branches targeting
  main, using the existing package-name validation and targeted build. Without
  this three-line selection change, this repair's MR would pass without ever
  building vtcode. No workflow, credentials, schedules or retry policy change.
- `scripts/ci/validate_mr_test.py`: runnable branch-selection regression test
  covering update, chiki, CI-fix, unrelated and invalid branch names.
- `docs/hermes-ci-status.md`: this task-owned evidence and handoff report.
- No schedule, retry policy or broad CI configuration change is justified by
  the observed compiler failure.

## Checks and delivery

- Initial `nix fmt`: passed, 478 files processed, 0 changed.
- `nix flake check --no-build --accept-flake-config`: passed on x86_64-linux.
  This is evaluation only, not a claim that every package was built.
- Final scoped `nix fmt`, `python3 scripts/ci/validate_mr_test.py -v`, canonical
  `nix build --no-link .#checks.x86_64-linux.ci-tests` and
  `nix flake check --no-build --accept-flake-config`: all passed at 01:00 UTC.
  The new regression method exercises eight branch/target combinations.
  The earlier hand-written unittest command failed because it omitted the
  canonical check's `PYTHONPATH`; no source fix was needed for that invocation
  error.
- Actual `nix build --accept-flake-config --no-link .#vtcode`: running in Herdr
  pane `wB:p1S`. Build log and output-path files are outside the repository at
  `/home/smaximov/src/llm-agents-hermes-ci-build.{log,paths}`.
- Read-only GLM Flash scout runs in Herdr `wB:p1T` with no write ownership.
- Commit/bookmark IDs, remote SHA readback and terminal validation pipeline
  results will be recorded after the build and push. Completion is not claimed.

## Remaining actions

1. Complete the actual package build and repository checks, fixing any further
   causal failures rather than bypassing them.
1. Commit on a task-owned `ci-fix/` bookmark, push without force, read back the
   remote SHA, and run MR validation to a terminal result.
1. Monitor maintenance pipeline 10408 to its terminal result and check exact
   parent/default/fork comparisons again. Preserve every fork commit.
1. Record terminal evidence and any residual integration or platform blockers.
