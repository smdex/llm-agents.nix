{
  lib,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  cmake,
  openssl,
  libxcb,
  dbus,
  versionCheckHook,
  cacert,
  librusty_v8,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ../goose-cli/hashes.json);
in
rustPlatform.buildRustPackage rec {
  pname = "goose";
  inherit (versionData) version cargoHash;

  src = fetchFromGitHub {
    owner = "aaif-goose";
    repo = "goose";
    rev = "v${version}";
    inherit (versionData) hash;
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

  meta = with lib; {
    description = "Server for Goose, a local extensible AI agent";
    homepage = "https://github.com/aaif-goose/goose";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "goosed";
  };
}
