{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  cmake,
  openssl,
  libxcb,
  dbus,
  versionCheckHook,
  cacert,
  callPackage,
  librusty_v8 ? callPackage ../goose-cli/librusty_v8.nix {
    inherit (callPackage ../goose-cli/fetchers.nix { }) fetchLibrustyV8;
  },
}:

rustPlatform.buildRustPackage rec {
  pname = "goosed";
  version = "1.41.0";
  cargoHash = "sha256-dnqj+aE/wu3vtt6yMJM9+mY+XHfbKA8KtlJnj0AsTIA=";

  src = fetchFromGitHub {
    owner = "aaif-goose";
    repo = "goose";
    tag = "v${version}";
    hash = "sha256-6hTjZnrTyFOhWLTLN/sa7IAXQVcQ/08gWz21KEGANAE=";
  };

  nativeBuildInputs = [
    pkg-config
    cmake
    rustPlatform.bindgenHook
  ];

  dontUseCmakeConfigure = true;

  buildInputs = [
    openssl
    libxcb
    dbus
  ];

  nativeCheckInputs = [ cacert ];
  env.RUSTY_V8_ARCHIVE = librusty_v8;

  cargoBuildFlags = [
    "--package"
    "goose-server"
  ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = "${placeholder "out"}/bin/goosed";

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Legacy Goose server for the Electron desktop integration";
    homepage = "https://github.com/aaif-goose/goose";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "goosed";
    platforms = [ "x86_64-linux" ];
  };
}
