{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  versionCheckHook,
}:

# Source build works without a wasm32/trunk toolchain: the daemon embeds
# crates/rookery-dashboard/dist via include_dir!, and upstream commits the
# trunk-built dashboard assets to the repo (only dashboard/target/ is
# gitignored), so `cargo build` picks them up as-is.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "rookery";
  version = "0.1.14";

  src = fetchFromGitHub {
    owner = "lance0";
    repo = "rookery";
    tag = "v${finalAttrs.version}";
    hash = "sha256-K/byotIr3BNsCUOaZiKj/vyyasgTQSZzhYvVQnwogmM=";
  };

  cargoHash = "sha256-W3JNmJsIOOxrgoSgaFJLS6KoB0Pi2WQrxnYtxa2K9Rw=";

  # Tests spawn helper processes and shell out to sqlite3 (see
  # rookery_engine::integrity), which is not available in the sandbox.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Local inference command center: manage llama-server and vLLM backends, hot-swap models, monitor GPU, and run agents from one daemon + CLI + live dashboard";
    homepage = "https://github.com/lance0/rookery";
    changelog = "https://github.com/lance0/rookery/releases/tag/v${finalAttrs.version}";
    license = [
      lib.licenses.mit
      lib.licenses.asl20
    ];
    # lance0 is defined inline (not in lib/default.nix) so this fork-only file
    # carries no delta on the upstream-owned maintainers list.
    maintainers = [
      {
        github = "lance0";
        githubId = 3323861;
        name = "lance";
      }
      flake.lib.maintainers.smdex
    ];
    mainProgram = "rookery";
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
