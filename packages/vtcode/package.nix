{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  openssl,
  libiconv,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "vtcode";
  version = "0.162.3";

  src = fetchFromGitHub {
    owner = "vinhnx";
    repo = "vtcode";
    tag = version;
    hash = "sha256-PQC0ATElqZmwmedgM81pPcS9xECAx3VReh8vUOgfHVg=";
  };

  cargoHash = "sha256-MSFC7RnDqNh1+D7rDYGEV1/NU+TnDcm5bPydec75XxI=";

  cargoBuildFlags = [
    "--bin"
    "vtcode"
  ];

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ openssl ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  preBuild = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'codegen-units = 1' 'codegen-units = 16' \
      --replace-fail 'lto = true' 'lto = "thin"'
  '';

  env.CARGO_BUILD_JOBS = "4";

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Terminal-native coding agent CLI";
    homepage = "https://github.com/vinhnx/vtcode";
    changelog = "https://github.com/vinhnx/vtcode/releases/tag/${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = platforms.all;
    mainProgram = "vtcode";
  };
}
