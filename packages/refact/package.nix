{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  versionCheckHook,
  versionCheckHomeHook,
}:

# NOTE: This package is marked as broken due to a nixpkgs cargo vendoring limitation.
#
# The rmcp git dependency (https://github.com/smallcloudai/rust-sdk) has a
# Cargo.toml with this pattern:
#
#   rmcp-macros = { version = "0.1", workspace = true, optional = true }
#
# This confuses nixpkgs' replace-workspace-values script which fails with:
#   "Unhandled keys in inherited dependency rmcp-macros: {'version': '0.1'}"
#
# The script expects EITHER `version = "X"` OR `workspace = true`, not both.
#
# Workarounds:
# 1. Build from source: git clone && cargo build --release
# 2. Use IDE plugins (VSCode, JetBrains) which bundle the engine
# 3. Wait for nixpkgs PR #XXXXX to be merged
#
# To test if this is fixed: nix build --impure --expr 'import <nixpkgs> { config.allowBroken = true; }'.refact

rustPlatform.buildRustPackage rec {
  pname = "refact";
  version = "7.0.2-unstable-2025-03-10";

  src = fetchFromGitHub {
    owner = "smallcloudai";
    repo = "refact";
    rev = "e4238702047505d74a19c695d9c6d6451ed2d867";
    hash = "sha256-j/Ox6QIw4Zx03Rpor7saKL/FLexfMdMVlOZy+n+jopQ=";
  };

  # Build only the engine crate
  buildAndTestSubdir = "refact-agent/engine";

  cargoLock = {
    lockFile = ./Cargo.lock;
    # Use builtin git fetcher for git dependencies
    allowBuiltinFetchGit = true;
  };

  nativeBuildInputs = [ pkg-config ];

  # Disable voice feature to avoid whisper-rs dependency
  buildNoDefaultFeatures = true;

  # Tests require network access and external dependencies
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Open-source AI Software Development Agent";
    homepage = "https://refact.ai";
    changelog = "https://github.com/smallcloudai/refact/releases";
    downloadPage = "https://github.com/smallcloudai/refact/releases";
    license = licenses.bsd3;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ ];
    mainProgram = "refact-lsp";
    platforms = platforms.unix;
    # Broken due to nixpkgs cargo vendoring issue with workspace inheritance in git deps
    # See: https://github.com/NixOS/nixpkgs/issues/XXXXX
    broken = true;
  };
}
