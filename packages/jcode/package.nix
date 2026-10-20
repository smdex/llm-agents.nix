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
  version = "0.99.0-smdex.1";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "jcode";
    # Pin the fork's verified feature revision rather than its release tag.
    rev = "0fa8c938a300de3e5d4559e18bb127fb39dcc9f0";
    hash = "sha256-xac+UaaQWUESuuWpyzUtCH3fVznGK9ztDvyy0VZ8hBI=";
  };

  cargoHash = "sha256-Fhi2doaeuAvskw/RmVAdW8V6XjJLmJc21uIbjF5fQgY=";

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
    JCODE_BUILD_SEMVER = finalAttrs.version;
    JCODE_BUILD_GIT_HASH = "0fa8c938a";
  };

  # Test suite needs network access, provider credentials and a TTY.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHomeHook ];
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/jcode -V | grep -F "v${finalAttrs.version}"
    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "RAM-efficient coding agent TUI with multi-model support and swarm coordination";
    homepage = "https://github.com/smdex/jcode";
    changelog = "https://github.com/smdex/jcode/commits/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "jcode";
    platforms = platforms.unix;
  };
})
