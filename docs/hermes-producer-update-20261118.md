# Producer update, November 18, 2026

## Status and approval boundary

**READY for Hermes exact-diff review against the explicitly requested upstream snapshot. Not released for consumer use.** Hermes owns exact-diff publication approval. No push, published-branch merge, deployment, restart, garbage collection, credential change or test disabling was performed. Consumer remains inventory-only.

Repository: /home/smaximov/src/llm-agents.nix. Sole producer writer uses the isolated shared-store JJ workspace /home/smaximov/src/llm-agents-hermes-producer. The original preexisting sheprd conflict/untracked directory is untouched; its recorded SHA256 passed readback at 14:09 UTC. The preexisting main bookmark conflict was not changed.

## Immutable integration and selected scope

- Previous verified handoff: 12bc90a7575718677833ad419f9655287bfa822f.
- Requested upstream: 6b0412eca7185b505fa46e39831e3858ad94383c.
- Forward-only integration: a35d6852f022c63226b31d158957f9aebccd2b09.
- Integration parents: previous handoff, GitLab chiki 3c88dfaa469a2137ceaa93e879fd24d23ec00881, requested upstream. Both published fork main histories are ancestors. No fork commits were discarded.
- Verified focused jcode repair commit: b356753499f54cdc571117bff7347377d5d22554.
- Exact subsequent candidate/final SHA is recorded outside the self-referential report in the durable ledger and evidence/candidate.sha.

Fourteen conflicted paths were reviewed. The verified smdex Jcode/Multica/Paseo recipes were retained instead of generic same-name upstream replacements. Newer fork Copilot Language Server and Dolt definitions were preserved with their matching hashes/lockfiles. Newer upstream command-code/omp and ordering-only hash changes were integrated. Existing CI fixes remain unchanged relative to the previous handoff in scripts/ci, .github/ci and checks/ci-tests.nix.

Fresh readback at **14:09:32 UTC** found upstream main had advanced to **f2c2ae96e351bc6a52d6f4fabfb9112c89610ccd**, another **40 commits after the explicitly requested snapshot**. Those later commits are not silently included or claimed integrated. This bounded candidate targets the requested 6b0412ec snapshot, not an indefinitely moving upstream HEAD.

| Published fork ref | Exact readback SHA | Requested-upstream-only / fork-only |
| --- | --- | --- |
| GitHub main | de633340f6a52f5468732d36677b51062609a398 | 211 / 72 |
| GitHub chiki | 12bc90a7575718677833ad419f9655287bfa822f | 139 / 88 |
| GitLab main | e343053977ca84cdbec3c418646bfa567e4d03e8 | 211 / 86 |
| GitLab chiki | 3c88dfaa469a2137ceaa93e879fd24d23ec00881 | 211 / 167 |

The remote forks do not match each other. No publication has attempted to hide or overwrite those differences. Exact initial and refreshed comparisons are retained in compare.log and final-refs.log.

## Fork source policies, refreshed readback

| Package | Selected source | Policy |
| --- | --- | --- |
| jcode | released v0.99.2-smdex.14, bb396231046153237b63ee6f3d1493e00c4d1bef | Latest released smdex tag. Main is 31e2d4700a580d0eabc0508cf0f3432492f68e50, deliberately not substituted for the release. |
| paseo and paseo-desktop | v0.16.0-smdex.5, ea96cb643a60b8d371ec5584851b3c3f0edadae8 | Actual latest fork tag and main are identical. |
| multica and multica-desktop | 21216761afcdba769e3b99a87e31dc142c0f9165 | Existing fork-main pin is current. |
| pi-perplexity | v0.6.3, 01194a1ac79750c037ab4523b64ba160f4dd9e29 | Source current; actual package/runtime version remains 0.1.0. |

## Complete custom inventory

All 41 entries are reconciled in evidence/custom-inventory-final.json, including actual commands, retained prior failures, final dispositions and changed paths versus the previous handoff. No final updater failures remain. Supported package-only updaters were used, never the full maintenance publisher. Four intentional pins and one manually verified fork leave 36 supported updater dispositions.

| Package | Final version | Disposition |
| --- | --- | --- |
| adversarial-spec | 0-unstable-2026-01-22 | supported updater passed |
| aizen | 0.7.4 | supported updater passed |
| cass | 0.11.0 | supported updater passed |
| caveman-code | 0.65.2 | supported updater passed |
| codedb | 0.2.5864 | supported updater passed |
| cowagent | 2.2.2 | supported updater passed |
| dirac | 0.6.1 | supported updater passed |
| empryo | 2.20.25 | supported updater passed |
| goose | 1.41.0 | existing intentional pin |
| goose-desktop | 1.60.1 | updated version/source hash, dependency hashes verified |
| goose-tui | 1.45.0 | existing intentional pin |
| goose2 | 0.1.0-unstable-2026-05-22 | corrected intentional component snapshot policy |
| happier | 0.2.21 | supported updater passed |
| happier-server | 0.2.21 | supported updater passed |
| herdr-gpui | 20261113.1-smdex.1 | existing intentional pin |
| jcode | 0.99.2-smdex.14 | current fork tag, native-library compatibility repaired |
| lazyskills | 1.2.0 | supported updater passed |
| loopx | 2.3.0 | supported updater passed |
| memsearch | 0.4.24 | supported updater passed |
| multica | 0.4.8-unstable-2026-10-08 | current supported fork updater |
| multica-desktop | 0.4.8-unstable-2026-10-08 | current supported fork updater |
| oh-my-codex-smdex | 0.21.9 | supported updater passed |
| openagent | 2.95.1 | supported updater passed |
| opendev | 0.1.9 | supported updater passed |
| openfang | 0.6.9 | supported updater passed |
| openhuman | 0.64.15 | supported updater passed |
| paseo | 0.16.0-smdex.5 | current supported fork updater |
| paseo-desktop | 0.16.0-smdex.5 | current supported fork updater |
| pi-perplexity | 0.1.0 | manually verified source tag v0.6.3 |
| rookery | 0.1.14 | supported updater passed |
| ruflo | 3.77.2 | supported updater passed |
| ruvector | 0.2.40 | supported updater passed |
| sheprd | 20261113.1-smdex.1 | supported updater passed in isolated producer workspace |
| skills-installer | 0.3.1 | supported updater passed |
| tura | 0.1.37 | supported updater passed |
| vibe-kanban | 0.1.46 | supported updater passed |
| vibecode-pro-max-kit | 3.2.5 | supported updater passed |
| vtcode | 0.183.1 | updated, source/Cargo hashes resumed and verified |
| waggle | 0.5.3 | supported updater passed |
| wintermolt | 0.7.0 | supported updater passed |
| xerj | 1.0.0-rc.102 | supported updater passed |

## Causal repairs and retained failures

The initial updater sweep failed because nix-update's bundled Nix evaluated unrealized source paths returned by Determinate lazy flake metadata. Materialization reduced the failures, but its wrapper still prepended a different Nix version. One diagnosed failed-only repair used the identical installed nix-update implementation with a consistent native Nix PATH and invocation-only settings. All original terminal failures are retained. No global configuration, credentials or sandbox settings changed.

The release resolver then reported vtcode already current after an earlier partial version edit, without refreshing hashes. Actual source inspection caught this false-success boundary. A supported, sandboxed **nix-update --flake vtcode --version=skip** resumed only source and dependency hashing, exited 0 and changed both stale hashes. No extra release sweep or blind source-fetch retries were performed.

The new nixpkgs cargo setup hook requires system libraries. Real jcode builds first exposed AWS-LC discovery, then the incompatible explicit joined-prefix header layout, then libzstd. Native crate discovery already supports nixpkgs' namespaced AWS-LC modules, so the extra joined-prefix abstraction was removed. The whole hook was audited against actual vendored crates, and the recipe now supplies precisely AWS-LC, OpenSSL, oniguruma, sqlite, zstd and Rust jemalloc, with the established JEMALLOC_OVERRIDE. The changed vtcode lock likewise requires AWS-LC, sqlite and Rust jemalloc; its recipe was adjusted before the required build. Existing tests/version hooks and the vtcode four-job cap are unchanged.

Goose2 is the experimental GUI pinned to 612cd89d515f16c84f70b4c74247e270277fe7ba, May 22, 2026. Its component Cargo.toml says 0.1.0; stable Goose v1.60.1 does not contain that component. Prior CI had only advanced an unrelated stable version label. The recipe now truthfully names its snapshot, points its changelog at the actual source commit and skips unrelated release tracking. The GUI source, Doctor patch, private Goose 1.57.0 ACP backend and enabled install checks are preserved. This does not drop or replace the application.

## Actual terminal validation

All package/check builds use **--option builders ursa --max-jobs 0**, with existing invocation-only SSH identity selection through the unchanged native Nix helper. Actual logs show ssh://ursa builds. No expensive local fallback or remote evaluation-store substitution was used.

The immutable integration build produced eight successful attributes: paseo, multica, pi-perplexity, paseo-desktop, multica-desktop, ci-tests, updater-tests and treefmt. It correctly returned overall exit 1 because the original jcode recipe failed. The corrected jcode subsequently passed its actual Ursa build and enabled version check, output /nix/store/sqiwz7kr3pr0s2c7jsscdnxcajs8lqy6-jcode-0.99.2-smdex.14. These are real outputs, not derivation evaluation or updater-success substitutes.

The required final immutable build set is dirac, goose-desktop, goose2, happier, happier-server, jcode, multica, multica-desktop, paseo, paseo-desktop, pi-perplexity, ruflo and vtcode, their 13 package-layout checks, plus CI/updater/treefmt checks. Whole-flake no-build evaluation is also required. Candidate 095b70ded91763431edb2d05b4dcb396687f0e2c passed whole-flake no-build evaluation and all 29 required build attributes, aggregate exit 0 at 15:25 UTC. Exact output paths are retained in final-builds.json. The final report-inclusive revision and its repeated gates are recorded in the external ledger and final-report/ evidence, avoiding a self-referential commit identifier. No GUI session or optional exhaustive runtime is claimed. README generation passed with no changes. Canonical nix fmt precedes local commits.

## Durable evidence and next actions

Authoritative continuation directory: /home/smaximov/.hermes/campaigns/2026-11-17-mclan-update/producer-20261118. It contains ledger.json, this report and an evidence symlink to the retained campaign scratch directory. Exact command scripts, source archives, stdout/stderr, exit files and output JSON are retained there, including integration-build-results.tsv, jcode-system.*, retry-consistent-nix/, vtcode-hash-resume.*, custom-inventory-final.json and final-refs.log. Prior failed build/updater/observer logs were not erased. Observer time-window expiry is not a CI/build failure.

Next: Hermes reviews the exact final SHA and diff before authorizing any publication. Consumer remains gated until authorized publication and remote SHA readback. No engineering blocker remains for the requested snapshot after successful final-report readback. Fresh upstream drift of 40 commits remains explicitly outside this requested-snapshot candidate and must not be described as fully current upstream HEAD. No main/chiki bookmark was moved.

### Realized package outputs

| Package | Output under /nix/store |
| --- | --- |
| dirac | 91rd8f7d293y4i8b31zla7pndqchsgl2-dirac-0.6.1 |
| goose-desktop | nqfj4k7ijrd476wd31mm6byi9zgki544-goose-desktop-1.60.1 |
| goose2 | hss5g3nn1aiqyrxa8h8n5jmhkx7y2jfd-goose2-0.1.0-unstable-2026-05-22 |
| happier | d8ij77pxba4j886sn7lqrsfm0j8sa2gr-happier-0.2.21 |
| happier-server | gf4jkzpl1yy7pfw03wkmms0iqgm3j411-happier-server-0.2.21 |
| jcode | sqiwz7kr3pr0s2c7jsscdnxcajs8lqy6-jcode-0.99.2-smdex.14 |
| multica | hcjz7dk5pbncj788vg5w8jszfaqm3s40-multica-0.4.8-unstable-2026-10-08 |
| multica-desktop | 4p5xhk4l6hqnhp8dajz8lz1zz3h6fxpg-multica-desktop-0.4.8-unstable-2026-10-08 |
| paseo | 96s89pwnwscp20v4mjzi5g2s9ga1qvky-paseo-0.16.0-smdex.5 |
| paseo-desktop | 8bsfkdm8jak6mjxycak6hw1fcny3j04m-paseo-desktop-0.16.0-smdex.5 |
| pi-perplexity | jnyahzfh1fsh8hwaqjck9an9qyswyyxv-pplx-0.1.0 |
| ruflo | rxhidp44gc11rghpmzq2ly9x1ad5nvq4-ruflo-3.77.2 |
| vtcode | zcvhra6hxmf5zj4583y1lq2cgdf1lbh5-vtcode-0.183.1 |

The retained private Goose ACP backend passed 358 unit tests and its integration test, with existing upstream ignores/filters unchanged. Desktop package builds and FHS-like layout checks passed, but no interactive GUI session is claimed. Existing realized dependencies were reused where Nix matched their derivations; the final readback is not a claim that every cached dependency was recompiled.
