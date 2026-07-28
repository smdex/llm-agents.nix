{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "ai-memory";
  version = "1.19.2";

  src = fetchFromGitHub {
    owner = "akitaonrails";
    repo = "ai-memory";
    tag = "v${version}";
    hash = "sha256-cOWx6nWonPpjf8J05gaIgicapM+nuu9FQ/C0BCsuIsU=";
  };

  cargoHash = "sha256-jI/Tc6wKFXNxtIO9pG3WLKnZrwBkdbVzn4nKvSVulJw=";

  # Workspace ships many crates (web, mcp server, evals harness, ...). We only
  # need the user-facing CLI binary, so build just that target.
  cargoBuildFlags = [
    "--bin"
    "ai-memory"
  ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Long-term memory and cross-vendor handoff for AI coding agents";
    homepage = "https://github.com/akitaonrails/ai-memory";
    changelog = "https://github.com/akitaonrails/ai-memory/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "ai-memory";
    platforms = platforms.unix;
  };
}
