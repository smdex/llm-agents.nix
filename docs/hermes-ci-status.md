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
- Actual `nix build --accept-flake-config --no-link .#vtcode`: passed in Herdr
  pane `wB:p1S`. Output:
  `/nix/store/kmzfl2wq5p1xns8s42wcxy0g0c4ap9d4-vtcode-0.182.4`.
  The resulting binary reports `vtcode-core 0.182.4`. Build log and output-path
  files are outside the repository at
  `/home/smaximov/src/llm-agents-hermes-ci-build.{log,paths}`.
- aarch64-linux and aarch64-darwin vtcode derivations both evaluated
  successfully. They were not built on this x86_64-linux host.
- Read-only GLM Flash scouting and independent review completed in Herdr.
  Review found no actionable defect and confirmed the branch-selection
  regression fails against the parent and passes against the repair.
- Code commit: `dcb624b8f7e6de717017c591ba4b657f596b943a`, JJ change
  `pvmyvznn`, bookmark `ci-fix/vtcode`, parent
  `33e344dd7a25263837cb745f279e4156ca4fc4d2`.
- Plain `git push --dry-run` followed by plain `git push` created only
  `refs/heads/ci-fix/vtcode`. No force option or default/update-branch push.
  GitLab branch API readback returned the exact code commit SHA at 01:01 UTC.
- MR <https://git.fila.lab/smaximov/llm-agents.nix/-/merge_requests/36> targets
  main, without automatic merging. Its actual `merge_request_event` pipeline
  <https://git.fila.lab/smaximov/llm-agents.nix/-/pipelines/10410> has exact SHA
  `dcb624b8f7e6de717017c591ba4b657f596b943a`. Pipeline 10410 and job 35424
  **passed**, read back at 01:14 UTC. The real job logged `targeted build: vtcode`, built the Rust 1.100 toolchain and vtcode derivation, and finished
  `validate-mr: all checks passed` at 01:13:29 UTC. Pipeline finished
  01:13:39 UTC. This was not formatting-only validation.
- Long-running monitor for both 10408 and 10410 lives in Herdr pane `wB:p1V`,
  not a short-lived tool background task. Its log is outside the repository at
  `/home/smaximov/src/llm-agents-hermes-ci-monitor.log`.
- Completion is not claimed until actual build and terminal remote verdicts.

## Additional actual failure discovered during monitoring

- Maintenance job 35417 failed with allowed exit 1 at 01:02 UTC. Its only
  failed package was vibe-kanban: the latest release
  `v0.1.46.1794744340` no longer publishes the old tag-named source/frontend
  zip. It publishes platform binary zips instead. Job 35418 subsequently
  refused still-failing bot MR !35 with allowed exit 3. Those are actual
  failures, even if the overall maintenance pipeline later appears green.
- A second read-only GLM Flash scout empirically verified that the official
  `linux-x64-vibe-kanban.zip` contains the embedded frontend and the same
  license-key pattern. No key was printed or recorded. Extraction must treat
  the member as binary. The newer dot-timestamp tag also needs semver parsing.
- Minimal follow-up modifies `packages/vibe-kanban/{update.py,package.nix, update_test.py,hashes.json}`. Preserve source builds and existing platforms,
  select the exact current asset, fail if extraction is empty, retain explicit
  missing-asset errors, and test both timestamp formats. No `skipUpdate`,
  swallowed exceptions or broader allow-failure rules.
- The real updater successfully upgraded 0.1.44 to 0.1.46 and regenerated all
  hashes. The actual frontend and Rust source build passed at 01:35 UTC in
  Herdr `wB:p1S`, exit 0. Output:
  `/nix/store/xsr5b85iycyhwlr4imkgaqwnfxv2hcnf-vibe-kanban-0.1.46`.
  Log: `/home/smaximov/src/llm-agents-hermes-ci-vibe-build.log`.
- All eight vibe-kanban updater tests, `nix fmt`, the canonical CI-tests
  derivation, and `nix flake check --no-build` passed on the follow-up.
- Independent review identified a latent hash-attribution race: building the
  whole package with two dummy hashes can assign the first failure to the
  wrong key. The follow-up instead hashes `.cargoDeps` and
  `.frontend.pnpmDeps` directly, reusing the existing updater helper. The
  regression asserts both exact targets. The second real downgrade/update
  round trip passed at 01:38 UTC, exit 0, regenerating identical hashes with
  those exact targets. aarch64-linux and aarch64-darwin derivations evaluated
  successfully but were not built on this host.
- A package-specific `ci-fix/vibe-kanban` branch will exercise its actual remote
  build independently, without modifying the bot-owned update branch.

## Remaining actions

1. Complete the actual package build and repository checks, fixing any further
   causal failures rather than bypassing them.
1. Monitor the task-owned package-specific CI-fix MRs to terminal results.
   Only new CI-fix branches and fast-forward follow-ups are pushed.
   Integration into main and changes to bot-owned MR !35 are not performed.
1. Monitor maintenance pipeline 10408 to its terminal result and check exact
   parent/default/fork comparisons again. Preserve every fork commit.
1. Record terminal evidence and any residual integration or platform blockers.
