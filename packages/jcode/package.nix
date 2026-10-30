{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  openssl,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "jcode";
  version = "0.99.2-smdex.3";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "jcode";
    rev = "4a2fa6cf101c0cebcca48fccc6a19ef327ff9ded";
    hash = "sha256-vFpGIHC9ujMkz8pu2ojVPYzakDcB5wv/6qzBVrnwDNo=";
  };

  cargoHash = "sha256-MJPSMHUCT90/OUAjAkceU+kQzy8BWwrgbx3SXUcBFHQ=";

  # .cargo/config.toml caps builds at 4 jobs; let Nix parallelism decide.
  postPatch = ''
    rm .cargo/config.toml
  '';

  # aws-lc-sys (rustls provider) needs cmake; imap's default native-tls
  # backend links against system openssl.
  nativeBuildInputs = [
    cmake
    pkg-config
  ];

  buildInputs = [ openssl ];

  # Archives lack git metadata; preserve the verified fork version and revision.
  env = {
    JCODE_RELEASE_BUILD = "1";
    JCODE_BUILD_SEMVER = finalAttrs.version;
    JCODE_BUILD_GIT_HASH = builtins.substring 0 9 finalAttrs.src.rev;
  };

  # Test suite needs network access, provider credentials and a TTY.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  versionCheckProgramArg = [ "--version" ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "RAM-efficient coding agent TUI with multi-model support and swarm coordination";
    homepage = "https://github.com/1jehuang/jcode";
    changelog = "https://github.com/smdex/jcode/commits/${finalAttrs.src.rev}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "jcode";
    platforms = platforms.unix;
  };
})
