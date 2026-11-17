# Producer update, November 16 contract

## Status

**READY for Hermes publication review.** Fixed upstream snapshot integrated forward-only, all 41 custom attributes accounted for, all 15 frozen-source package/check builds passed, CLI version smokes passed, and the actual Ursa native-version regression passed. No engineering blocker remains. Publication approval remains with Hermes. No push, merge, cache publication, activation or deployment has been performed for this campaign.

## Scope and isolation

- Contract: `/home/smaximov/.hermes/cache/scratch/mclan-update-20261116-contract.md`, read in full.
- Producer repository: `/home/smaximov/src/llm-agents.nix`, host `plan`.
- Dedicated shared-store JJ workspace: `/home/smaximov/src/llm-agents-hermes-producer`, workspace `hermes-producer`. Not a divergent clone.
- Original workspace's preexisting sheprd conflict remains untouched. Other existing JJ workspaces are not campaign-owned.
- Repository instructions and relevant update/CI documentation were read. Requested `/home/smaximov/.config/agent-tooling/MEMORY.md` does not exist on this host.
- All builds, updaters and GLM-5.3-flash read-only scouts run in Herdr. Root is the sole producer writer. Hermes retains publication and merge approval.

## Exact initial remote comparison

Fresh fetch at approximately 2026-11-17 02:39 UTC, preserved under local `refs/hermes-producer/20261117-0238/`:

| Remote/ref | Exact revision | Upstream-only / fork-only |
| --- | --- | --- |
| numtide upstream main | `63097de80420a27b13b3d5116ce1134a705b7dd3` | reference |
| GitLab main and GitHub main | `de633340f6a52f5468732d36677b51062609a398` | 70 / 72 |
| GitLab chiki and GitHub chiki | `dfd301955d78cff6200a40eefc0f35f95d9b7159` | 70 / 83 |

Actual remotes: `ssh://git@git.fila.lab/smaximov/llm-agents.nix.git`, `ssh://git@github.com/smdex/llm-agents.nix.git`, and `https://github.com/numtide/llm-agents.nix.git`.

Forward-only local integration commit: `853dcadcf9701b0c011cdbfbaef5f3117834f4a7`, with both the exact chiki and upstream revisions above as parents. Three conflicts concerned only generic upstream version/source/dependency hash bumps in multica, multica-desktop and paseo-desktop. The existing smdex fork recipes were preserved rather than replaced by generic upstream packages. Canonical `nix fmt` passed with zero changes. Bubblewrap namespace preflight passed without host changes.

Supervisor requested one final upstream refresh, fixed at `97b2c73782356e4934a5d350fa4b6b7dbea1b646`. It was integrated forward-only in **`aadd7ef1ccfef285f2687b9f84b8468b7799dec1`**, whose parents are the focused task commit `9778bab8a89f4dc11290f1ed30f98a824b7d14ab` and that exact upstream snapshot. The only additional upstream conflict was generic Paseo version/source/dependency hashes. The verified smdex 0.16.0-smdex.5 recipe was preserved exactly. Both original fork chiki and fixed upstream are verified ancestors. Canonical formatting passed before both task commits. No indefinite moving-head chase.

Fresh independent remote readback at **2026-11-17 03:40:18 UTC** confirmed all three remote default branches are `main` and the chosen upstream snapshot is still current:

| Ref | Actual revision | Fresh upstream-only / fork-only | Remote-only / frozen producer-only |
| --- | --- | --- | --- |
| numtide/main | `97b2c73782356e4934a5d350fa4b6b7dbea1b646` | 0 / 0 | 0 / 86 |
| GitLab main = GitHub main | `de633340f6a52f5468732d36677b51062609a398` | 72 / 72 | 0 / 86 |
| GitLab chiki = GitHub chiki | `dfd301955d78cff6200a40eefc0f35f95d9b7159` | 72 / 83 | 0 / 75 |

Thus the **local frozen producer has zero upstream-only commits missing**, and preserves all currently published fork main/chiki commits. Published forks intentionally remain unchanged while Hermes reviews publication. Full evidence: `final-freeze-resume.log` and `final-remote-readback.log`. The original workspace still resolves to exact preexisting revision `7dd86e8ea00ac526eec04edd07d3a275350c66ec`, verified in `preservation-capacity.log`; its sheprd files were not edited. The preexisting global main bookmark conflict remains unresolved. Normal upstream fetch advanced the tracked `main@upstream` reference, without force-setting main or changing any published branch.

## Verified fork release/source policy

Primary GitHub API readback at approximately 02:47 UTC, repeated in the final 03:40 UTC remote readback with the same exact refs, retained in `fork-refs.log` and `final-remote-readback.log`:

| Package | Pinned source | Actual remote state | Disposition |
| --- | --- | --- | --- |
| jcode | smdex/jcode `v0.99.2-smdex.14`, tag commit `bb396231046153237b63ee6f3d1493e00c4d1bef` | latest fork tag is the same; fork main is `31e2d4700a580d0eabc0508cf0f3432492f68e50` | Latest released tag under existing smdex tag policy. Main is a different, rebased history with unreleased changes, not silently substituted. |
| paseo and paseo-desktop | smdex/paseo `v0.16.0-smdex.5` | tag and main both `ea96cb643a60b8d371ec5584851b3c3f0edadae8` | Current fork release and main. |
| multica and multica-desktop | smdex/multica `21216761afcdba769e3b99a87e31dc142c0f9165` | exact fork main matches; latest release tag is older v0.4.8 | Current intentional fork-main pin. Desktop inherits source/version. |
| pi-perplexity | smdex/pi-perplexity `01194a1ac79750c037ab4523b64ba160f4dd9e29` | exact main and latest v0.6.3 tag match | Source current. Upstream package.json and CLI itself still advertise 0.1.0, so runtime version pin is intentionally not relabeled 0.6.3. Stale changelog metadata corrected from v0.6.1 to v0.6.3. |

The complete inventory covers 36 fork-only package directories plus five shared fork overrides, 41 attributes total. `goose` and `goose-tui` are intentional legacy compatibility pins, not aliases. `herdr-gpui` is the compatibility alias for sheprd. No package is silently dropped.

## Running checks and evidence

Evidence directory: `/home/smaximov/.jcode/scratch/hermes-producer-20261116/`.

- `producer-ledger.json`: current machine-readable scope, exact refs, gate results/store paths, safety constraints and remaining work. `update-results.json` is the live per-package exit/disposition ledger.
- `inventory.log`: exact remotes, original state, remote refs and divergence.
- `sync-finish.log`: successful sandbox preflight, `nix fmt`, local integration commit.
- `packages-before.json`, `update-results.json`, `update-all.log`, `<package>.update.log`: supported package-only updater outcomes. No full maintenance/publisher entrypoint is invoked. No `UPDATE_SANDBOX=0`, sudo sysctl, GC or test disabling.
- `fork-refs.log`, `pi-perplexity-package.json`, `pi-perplexity-index.ts`: fork source/version comparisons.
- `build-forks.log`, `<package>.build.log`, `<package>.build.paths`, `fork-build-results.txt`, `<package>.smoke.log`: serialized real builds against immutable integration source, not drvPath evaluation.
- jcode build exited 0 with realized output `/nix/store/wch1687xr6s1sjdc3ssjlm30qn2jhfyh-jcode-0.99.2-smdex.14`. Isolated-HOME version smoke exited 0 and reports `jcode v0.99.2-smdex.14 (refs/tags)`. Paseo actual source build also exited 0 at 02:59:34 UTC, realized `/nix/store/q23ka6lll4yar5dmhlzgpyfy4aw7nw9h-paseo-0.16.0-smdex.5`; isolated-HOME executable version smoke exited 0 and reports `0.16.0-smdex.5`. Multica build and version smoke exited 0, realized `/nix/store/xsxh4l9l412mq9zdrf2bx4ygn8mrji3l-multica-0.4.8-unstable-2026-10-08`; it reports the exact pinned version and Go 1.27.3. Multica-desktop build exited 0, realized `/nix/store/8hg3a1862l1ffkkzp6w1vi4zj8qnpbcv-multica-desktop-0.4.8-unstable-2026-10-08`. Desktop GUI runtime is not claimed tested.
- CI/updater regression builds against immutable integration revision exited 0. Realized outputs: `/nix/store/w7aymybrrc99xzwlfb8371rzvbmv55kh-ci-tests-check` and `/nix/store/mq39gd0wxj1724l5dbv09g60pwksi6s5-updater-tests-check`. Paths and logs retained in `ci-regression.*`.

The immutable integration whole-flake `nix flake check --no-build` exited 0. This is evaluation coverage only, not claimed as package build coverage. Exact ancestry and the selected CI repair/vibe-kanban/vtcode paths were independently verified unchanged from the fork.

A targeted native-version check exposed a **preexisting stale test**: `test-native-version.cjs` tried to extract a Nix patch regex that the existing smdex.5 recipe had already removed. Both the old fork recipe and local integration lack that regex. The check was repaired to call the actual pinned source helper, preserving beta iOS slots, stripping fork suffixes, and rejecting invalid versions. The strengthened test exited 0 (`native-version-green.log`, `PASEO_NATIVE_VERSION_GREEN_EXIT=0`). The original failure and source/history diagnosis are retained in `check-freeze.log` and `native-test-diagnose.log`. No package tests were disabled.

Paseo-desktop initial build **failed**, not passed: npm dependency fetch hit an HTTP/2 framing error fetching `@esbuild/darwin-arm64` from registry.npmjs.org. This is an observed network fetch failure before app compilation, not evidence of a source regression. The single bounded unchanged-source retry **passed, exit 0**, realizing `/nix/store/gjisvnalvv96akkyxgadjammnphyrw1v-paseo-desktop-0.16.0-smdex.5`; original failure remains in `paseo-desktop.build.log` and successful retry evidence in `paseo-desktop.retry.*`. No sandbox or network security setting was relaxed. Shared Plan storage remained approximately 38 GiB free after the serialized builds; no GC.

## Required Ursa builder gate

At 03:17:57 UTC the user required all subsequent package/check builds to use exact `--option builders ursa`, with no silent expensive local fallback. Previously started updater/build commands were not interrupted. A new actual regression derivation was evaluated locally and submitted with:

```bash
nix build --option builders ursa --max-jobs 0 --no-link --print-out-paths -L \
  --file /home/smaximov/.jcode/scratch/hermes-producer-20261116/native-version-check.nix
```

This exited 1 before test execution. `ursa-native-version.log` proves `ssh://ursa` attempted `root@ursa` and failed with `Permission denied (publickey,keyboard-interactive)`. Derivation: `/nix/store/hk3j1qnk26waqz8g7lwra4yssfkkf31v-paseo-native-version-producer-check.drv`. Nix explicitly refused local execution because `max-jobs = 0`. The initial invocation is an observed authentication failure, not a test assertion failure or host outage. Subsequent supervisor evidence proved user SSH works. The existing SSH agent socket is valid but holds no identities, and installed Nix reports `ssh-auth-sock` is not a setting. An explicit existing identity succeeds for root SSH without changing keys, accounts or configuration. A per-invocation `build-hook` environment prefix now reuses the installed Nix `__build-remote` helper with `NIX_SSHOPTS=-i<existing-identity-path>`. Its log shows the actual derivation **building on `ssh://ursa`**, with local execution disabled. The check **passed, exit 0**, with output `/nix/store/a7g36m31bh0c2dzmmdagmfzgnaz8ns8y-paseo-native-version-producer-check` copied back from `ssh://ursa`. This is an actual remote execution, not a substituted/cached-only claim. Evidence is `auth-native-probe.log`, `ursa-auth-check.sh`, `ursa-auth-check.log`, and `ursa-native-version-explicit.*`. The blocker was resolved without operator intervention, account changes, key copying, permission changes, global configuration changes, remote evaluation-store substitution or local build fallback.

Pi-perplexity actual build and isolated-HOME `pplx --version` smoke completed before this steering, both exit 0. Realized output `/nix/store/72l49qd6a94wj4hc8b4vx3a44q4gpp58-pplx-0.1.0`, runtime `0.1.0`, consistent with the actual v0.6.3 source.

## Full custom inventory

Supported package-only updates completed: **37 updater successes**, including Paseo-desktop after its network-failed first attempt, three deliberate `skipUpdate` pins, and one current manual source/tag review. The bounded supported updater retry passed exit 0 (`paseo-desktop.retry-update2.log`), reporting 0.16.0-smdex.5 with no package changes. It inherited the same Ursa-only invocation settings for nested Nix commands. The unchanged-source desktop package build retry also passed. No updater changed a recipe version or source pin. `GITHUB_OUTPUT` change flags were not trusted as per-package changes because the task-owned report/metadata edits made the working tree dirty.

| Attribute | Version | Disposition |
| --- | --- | --- |
| adversarial-spec | 0-unstable-2026-01-22 | current, updater exit 0 |
| aizen | 0.7.4 | current, updater exit 0 |
| cass | 0.11.0 | current, updater exit 0 |
| caveman-code | 0.65.2 | current, updater exit 0 |
| codedb | 0.2.5864 | current, updater exit 0 |
| cowagent | 2.2.2 | current, updater exit 0 |
| dirac | 0.6.0 | current, updater exit 0 |
| empryo | 2.20.25 | current, updater exit 0 |
| goose | 1.41.0 | pinned legacy server, later releases removed goose-server |
| goose-desktop | 1.59.2 | current, updater exit 0 |
| goose-tui | 1.45.0 | pinned legacy TUI source |
| goose2 | 1.59.2 | current, updater exit 0 |
| happier | 0.2.20 | current, updater exit 0 |
| happier-server | 0.2.20 | current, updater exit 0 |
| herdr-gpui | 20261113.1-smdex.1 | compatibility alias for sheprd, intentional skipUpdate |
| jcode | 0.99.2-smdex.14 | current released smdex tag, updater exit 0 |
| lazyskills | 1.2.0 | current, updater exit 0 |
| loopx | 2.3.0 | current, updater exit 0 |
| memsearch | 0.4.24 | current, updater exit 0 |
| multica | 0.4.8-unstable-2026-10-08 | current fork-main pin, updater exit 0 |
| multica-desktop | 0.4.8-unstable-2026-10-08 | inherits current fork source, updater exit 0 |
| oh-my-codex-smdex | 0.21.9 | current, updater exit 0 |
| openagent | 2.95.1 | current, updater exit 0 |
| opendev | 0.1.9 | current, updater exit 0 |
| openfang | 0.6.9 | current, updater exit 0 |
| openhuman | 0.64.15 | current, updater exit 0 |
| paseo | 0.16.0-smdex.5 | current fork tag and main, updater exit 0 |
| paseo-desktop | 0.16.0-smdex.5 | current, updater retry exit 0, package build exit 0 |
| pi-perplexity | 0.1.0 | current v0.6.3 source manually verified, upstream runtime is 0.1.0 |
| rookery | 0.1.14 | current, updater exit 0 |
| ruflo | 3.77.1 | current, updater exit 0 |
| ruvector | 0.2.40 | current, updater exit 0 |
| sheprd | 20261113.1-smdex.1 | current, updater exit 0 |
| skills-installer | 0.3.1 | current, updater exit 0 |
| tura | 0.1.37 | current, updater exit 0 |
| vibe-kanban | 0.1.46 | current, updater exit 0 |
| vibecode-pro-max-kit | 3.2.5 | current, updater exit 0 |
| vtcode | 0.182.4 | current, updater exit 0 |
| waggle | 0.5.3 | current, updater exit 0 |
| wintermolt | 0.7.0 | current, updater exit 0 |
| xerj | 1.0.0-rc.102 | current, updater exit 0 |

## Final frozen-source acceptance

Immutable tested revision: **`aadd7ef1ccfef285f2687b9f84b8468b7799dec1`**. `final-checks.sh` finished with **`PRODUCER_FINAL_CHECKS_EXIT=0`**, and `final-build-results.tsv` records **15 builds/checks, all exit 0**. Commands were serialized and used exact `--option builders ursa --max-jobs 0`, plus the verified invocation-only authentication prefix. Local expensive fallback was disabled, not merely discouraged.

```bash
nix build --accept-flake-config --option builders ursa --max-jobs 0 \
  --option build-hook "$(command -v env) NIX_SSHOPTS=-i$HOME/.ssh/id_ed25519 $(nix config show build-hook)" \
  --no-link --print-out-paths -L \
  'git+file:///home/smaximov/src/llm-agents.nix?rev=aadd7ef1ccfef285f2687b9f84b8468b7799dec1#<attribute>'
```

| Built attribute | Realized output | Runtime evidence |
| --- | --- | --- |
| jcode | `/nix/store/wch1687xr6s1sjdc3ssjlm30qn2jhfyh-jcode-0.99.2-smdex.14` | isolated-HOME version 0.99.2-smdex.14, exit 0 |
| paseo | `/nix/store/q23ka6lll4yar5dmhlzgpyfy4aw7nw9h-paseo-0.16.0-smdex.5` | isolated-HOME version 0.16.0-smdex.5, exit 0 |
| paseo-desktop | `/nix/store/gjisvnalvv96akkyxgadjammnphyrw1v-paseo-desktop-0.16.0-smdex.5` | executable/share layout passed, GUI not launched |
| multica | `/nix/store/xsxh4l9l412mq9zdrf2bx4ygn8mrji3l-multica-0.4.8-unstable-2026-10-08` | isolated-HOME exact pinned version, exit 0 |
| multica-desktop | `/nix/store/8hg3a1862l1ffkkzp6w1vi4zj8qnpbcv-multica-desktop-0.4.8-unstable-2026-10-08` | executable/share layout passed, GUI not launched |
| pi-perplexity | `/nix/store/72l49qd6a94wj4hc8b4vx3a44q4gpp58-pplx-0.1.0` | isolated-HOME pplx version 0.1.0, exit 0 |

The final package requests reused already-realized matching outputs. They are real `nix build` successes against the frozen source, but are **not claimed as fresh Ursa package compilations**. Earlier real source builds and their original logs remain documented above. Fresh Ursa execution is separately proven for the native-version derivation and affected regression/treefmt checks.

All six `checks.x86_64-linux.pkgs-{jcode,paseo,paseo-desktop,multica,multica-desktop,pi-perplexity}` passed. Exact check store paths are in `final-checks.x86_64-linux.pkgs-*.paths`. Final CI/updater regression and treefmt outputs were:

- `/nix/store/h0rzlxq8pvw8a4yxib32f9mjrz8hskcc-ci-tests-check`
- `/nix/store/sr2291fgyxb7jmvilrs4xkc6f2dp2bw2-updater-tests-check`
- `/nix/store/35qjy26lm714v18p7al48wzj729ga9sv-treefmt-check`

Their `final-checks.x86_64-linux.*.log` files show actual builds on `ssh://ursa` and output copy-back. Treefmt processed 482 files with zero changes. Whole-flake `nix flake check --no-build` also passed exit 0, retained in `final-flake-eval.log`; this is separately classified as evaluation-only coverage. `packages-final.json` exactly matches the initial 41-attribute version/skipUpdate inventory. The remotely executed native regression script is byte-identical to the frozen commit (`remote-test-input-identity.log`, exit 0), and the final Paseo source path is exactly the tested `/nix/store/ydrdcy9yz5knkyrjczr478p9icccdzpz-source`.

## Reviewable changes and handoff

Beyond the upstream integrations, only three task-owned paths changed from the original integrated source:

1. `packages/paseo/test-native-version.cjs`: repair the preexisting stale regex-extraction test by testing the actual pinned source helper and boundary cases.
1. `packages/pi-perplexity/package.nix`: correct stale changelog metadata to the already-pinned v0.6.3 source. No false runtime version bump.
1. `docs/hermes-producer-update-20261116.md`: this evidence report.

Local commit chain is initial integration `853dcadcf9701b0c011cdbfbaef5f3117834f4a7`, focused verification/test/metadata commit `9778bab8a89f4dc11290f1ed30f98a824b7d14ab`, and final upstream merge `aadd7ef1ccfef285f2687b9f84b8468b7799dec1`. The report-only handoff descendant is held by task-owned local bookmark **`hermes-producer-20261116`**. Its exact SHA and final aggregate build readback are recorded after commit in `producer-ledger.json` and `handoff-builds.json` under the evidence directory. The handoff aggregate rechecks all six packages and nine checks against that exact report-inclusive revision, not an unpublished remote assumption.

### Residual gates owned by Hermes and the consumer

- Hermes reviews the local bookmark and evidence, chooses the publication branch/MR policy, and explicitly approves publication. No publication has been attempted. No merge or push is implied by READY.
- After approved publication, read back its remote SHA before consumer lock updates. The Coma consumer must lock the published verified revision, never a committed `path:` override or the old remote main.
- Consumer owner then performs the requested package and all three host toplevel builds under its separate contract. This producer report does not claim those consumer builds or any GUI interaction, login, activation or deployment.
- No outstanding producer engineering blocker remains. The initial npm HTTP/2 failures and daemon identity mismatch were recovered with retained failing and passing evidence, not hidden or bypassed.
