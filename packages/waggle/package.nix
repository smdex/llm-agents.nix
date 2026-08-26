{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "waggle";
  version = "0.5.3";

  src = fetchFromGitHub {
    owner = "modiqo";
    repo = "waggle";
    tag = "v${finalAttrs.version}";
    hash = "sha256-My0MIJwJ4eQ4Z9DNN539jGxRkNkLcqlrsMqHtMyDd7Y=";
  };

  cargoHash = "sha256-lAJRFjxbX8MjYaQiWAxzz1rjiFePh7Ggx9+vmk/m5Yw=";

  # Virtual workspace whose members also carry helper binaries (xtask,
  # waggle-bench) and a wasm-only edge worker; build just the two
  # user-facing CLIs so nothing else lands in $out/bin.
  cargoBuildFlags = [
    "--package=waggle-cli"
    "--package=waggle-tmux"
  ];

  # The integration tests spawn waggle daemons on unix domain sockets and
  # mutate $HOME; the CLI itself is exercised via versionCheckHook.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Attributed, resolvable artifact references for agent handoffs — a ~30-byte token instead of pasted context, MCP-native";
    homepage = "https://github.com/modiqo/waggle";
    changelog = "https://github.com/modiqo/waggle/releases/tag/v${finalAttrs.version}";
    license = with licenses; [
      mit
      asl20
    ];
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "waggle";
    platforms = platforms.unix;
  };
})
