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
  version = "1.30.0";

  src = fetchFromGitHub {
    owner = "akitaonrails";
    repo = "ai-memory";
    tag = "v${version}";
    hash = "sha256-xXlrd+aIoIqWpbMlLXYoVjJrzZS2nTmSKj0S1FcFiI0=";
  };

  cargoHash = "sha256-ixwBh2sqVIAPQIL6wA5ljM/yRnz3s41R69fn/BYitbQ=";

  # Workspace ships many crates (web, mcp server, evals harness, ...). We only
  # need the user-facing CLI binary, so build just that target.
  cargoBuildFlags = [
    "--bin"
    "ai-memory"
  ];

  # install-hooks reads the bundled `hooks/` tree from disk at runtime. Of the
  # candidate paths it probes, `/usr/share/ai-memory/hooks/<agent>` is the one
  # documented for native Linux packages, so repoint it at the Nix store and
  # ship the tree there. (install-skills/install-instructions are compile-time
  # embedded via include_str!, so they need no runtime resources.)
  postPatch = ''
    substituteInPlace crates/ai-memory-cli/src/commands/install_hooks.rs \
      --replace-fail '/usr/share/ai-memory/hooks/' '${placeholder "out"}/share/ai-memory/hooks/'
  '';

  postInstall = ''
    mkdir -p $out/share/ai-memory
    cp -r hooks $out/share/ai-memory/hooks
  '';

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
