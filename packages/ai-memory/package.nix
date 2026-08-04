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
  version = "1.24.0";

  src = fetchFromGitHub {
    owner = "akitaonrails";
    repo = "ai-memory";
    tag = "v${version}";
    hash = "sha256-ivP2TZM+OvNd1KcYolc7s+Ut++Mf8nA+xnjSUpGCOKI=";
  };

  cargoHash = "sha256-7PfpFhLa3dIn7sjt2UhdK0BGfRy7PJWBm5GUUxaJXQw=";

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
