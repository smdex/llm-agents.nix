# Code Context

## Findings
1. **Upstream repo confirmed**: `https://github.com/smdex/pi-perplexity` — "pi extension to search the Web search via your Perplexity Pro/Max subscription", last push 2026-10-07.
2. **CLI source**: `cli/` subtree in that repo; `cli/package.json` = `"name": "pplx-cli", "version": "0.1.0", "bin": {"pplx": "./src/index.ts"}` (private, bun/yargs).
3. **Local install matches**: `~/.nix-profile/bin/pplx` → `/nix/store/wy552ydhfhxvp25i3hnlpfy16k5d4r9w-pplx-0.1.0/bin/pplx`, version `0.1.0`, bun-shebang binary (bun-compiled from repo `package.nix`, installed via `nix profile` — flake attr `packages.x86_64-linux.pplx`). Version and bin name exactly match upstream `cli/package.json`.
4. **Skill confirms intent**: `~/.pi/agent/skills/perplexity-cli/SKILL.md` — "`pplx` CLI... repo `pi-perplexity/cli`... NixOS: `nix profile install -f .` from the pi-perplexity repo". Matches installed binary.
5. **npm `pi-perplexity` package not the intended CLI**: intended tool is the GitHub repo's `cli/` workspace (`pplx-cli`), not any npm-published `pi-perplexity`. Root repo also has a separate extension entry (`src/cli.ts`, search client) — that is the pi extension, not the `pplx` binary.

## Conclusion
Intended CLI: **`pplx` v0.1.0**, upstream `https://github.com/smdex/pi-perplexity` (`cli/` package `pplx-cli`, bin `pplx` → `cli/src/index.ts`), locally installed as bun-compiled Nix profile package.