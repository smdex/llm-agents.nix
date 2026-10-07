{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  cmake,
  pkg-config,
  openssl,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "jcode";
  version = "0.92.1-smdex.1";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "jcode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-zX6JDsjXi4xNbXXHtvoyPif7HFUSC86y/VMVsZV+pcA=";
  };

  cargoHash = "sha256-4hjX4mkefjIrYpxicwqGmCWyVQKyz2NVcXgn7Aj/J8Q=";

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

  # Make the embedded version string a release one ("vX.Y.Z") instead of a
  # dev one; the build script falls back to "unknown" git metadata, which is
  # fine for tarball builds.
  env = {
    JCODE_RELEASE_BUILD = "1";
    JCODE_BUILD_SEMVER = "0.92.1";
    JCODE_BUILD_GIT_HASH = "da075227";
  };

  # Test suite needs network access, provider credentials and a TTY.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHomeHook ];
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/jcode -V | grep -F "v0.92.1"
    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "RAM-efficient coding agent TUI with multi-model support and swarm coordination";
    homepage = "https://github.com/smdex/jcode";
    changelog = "https://github.com/smdex/jcode/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "jcode";
    platforms = platforms.unix;
  };
})
