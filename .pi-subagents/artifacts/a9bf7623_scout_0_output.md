# Code Context

## Files Retrieved
1. `packages/jcode/package.nix` (lines 1-20, 56-65) — main: src = `1jehuang/jcode` v0.92.0 (upstream); maintainer smdex.
2. `packages/jcode/update.py` (whole) + `update_test.py` — added on main (c7f77e88) to track **smdex/jcode fork** branch `main` (`--version=branch=main --src-only`, version read from fork Cargo.toml).
3. `chiki:packages/jcode/package.nix` — chiki: src = `smdex/jcode`, `rev = 1b434d4ceed0ff93265153cf2012a24cd214025a` (fork already used on chiki).
4. `packages/paseo/package.nix` (lines 1-60) — main: `getpaseo/paseo` v0.10.3, buildNpmPackage, custom node-pty build.
5. `chiki:packages/paseo/package.nix` (lines 24-29) — chiki: `smdex/paseo`, `rev = 36767d553263c8111a8b2d7d8d5972a20050273f`, version `0.11.0-beta.5`; chiki also modified `packages/paseo-desktop/package.nix` (chiki commit e98368a9 stat).
6. `packages/multica/package.nix` (whole) — main: `multica-ai/multica` v0.6.1, Go module; **no fork** anywhere yet.
7. `packages/pi/package.nix` (lines 1-60) — precedent for packaging pi-ecosystem npm packages (`@earendil-works/pi-coding-agent`, hashes.json pattern).

## jj state
- `@` = `lsmqlwszutyl`, description **(empty)**, diff **no** → clean, free to work.
- Remotes: `origin` = git@github.com:smdex/llm-agents.nix (fork), `upstream` = https://github.com/numtide/llm-agents.nix.git.
- Bookmarks: `main*` @ oowpx (ruflo 3.54.1), `chiki` @ sklpp (e98368a9 "paseo: pin native Jcode fork for chiki testing").
- **chiki is NOT atop main**: `chiki::main` and `main::chiki` both empty; merge-base = a25d64c8. chiki's parent is an older copy of "jcode: track smdex fork customizations on main" (3bee67ea) while main has a newer rebased copy (c7f77e88, Oct 7 04:41) plus `jcode: 0.91.0 -> 0.92.0` (be6b4be9). chiki needs rebase onto main.

## Upstream presence evidence (GitHub API, read-only)
- `numtide/llm-agents.nix` packages: **jcode → exists (200)**, **multica → exists (200)**, **paseo → 404**, **pi-perplexity → 404**.
- Forks on GitHub (all exist, default branch main): `smdex/jcode` (pushed 2026-10-07), `smdex/paseo` (2026-10-07), `smdex/multica` (2026-07-23).

## pi-perplexity identity (npm, read-only)
- npm `pi-perplexity` 0.4.0 (2026-07-16), MIT, author ivanrvpereira, repo `ivanrvpereira/pi-perplexity`.
- **NOT a CLI**: `keywords: ["pi-package","pi-extension"]`, no `bin`, `main: src/index.ts`, `pi.extensions: ["./src/index.ts"]`, peerDeps `@earendil-works/pi-tui` + `@earendil-works/pi-ai`. It's a pi-coding-agent extension installed via `pi install npm:pi-perplexity` (Perplexity Pro/Max web search). Packaging must follow pi-extension precedent, not `mainProgram` CLI pattern.

## Recommended safe jj sequence
1. `jj git fetch` (updates upstream/main; local main oowpx may be behind upstream head c9ef0fb — verify before moving bookmarks).
2. Rebase chiki onto main: `jj rebase -d main` with `-r chiki` (or `jj rebase chiki -d main`), resolve conflict between duplicate "jcode: track smdex fork" commits (c7f77e88 vs 3bee67ea) and jcode 0.92.0 bump.
3. On chiki: `jj new chiki -m "multica: use smdex fork"` (+ any jcode/paseo fork tweaks — already forked on chiki). Constraint: jcode & multica exist in numtide upstream, so fork switches are **chiki-only**; paseo & pi-perplexity are not upstream, so free on main.
4. pi-perplexity on main: `jj new main -m "pi-perplexity: init at 0.4.0"` (buildNpmPackage, no bin/mainProgram — see ambiguity).
5. Run `nix fmt`, build `.#pi-perplexity` etc., `nix flake check`.

## Ambiguities
1. **pi-perplexity "CLI" premise wrong** — upstream is a pi extension with no executable bin. Need decision: package as extension-only npm package, or skip/scope-change.
2. **Constraint conflict**: `packages/jcode/update.py` on main already points updater at smdex fork, and that commit lives on main — while "exists in numtide → modifications on chiki only". Confirm whether update.py may stay on main or must move to chiki during rebase.
3. Local `main` vs `upstream/main` (c9ef0fb) divergence unverified — sync direction needs confirmation.
4. smdex/multica fork stale (last push 2026-07-23) vs multica-ai v0.6.1 — pin rev/tag strategy on a stale fork unclear.