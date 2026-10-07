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
  version = "0.91.0";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "jcode";
    rev = "1b434d4ceed0ff93265153cf2012a24cd214025a";
    hash = "sha256-xuNwx8lHDBk7d4tNMlRoXpFWwgNwlzP4kIEZt1jQsr4=";
  };

  cargoHash = "sha256-p5qKX+MFC44aZ5OZ5iJxCj0sY6pdQMsEPNzuXdmsd3Q=";

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
  env.JCODE_RELEASE_BUILD = "1";

  # Test suite needs network access, provider credentials and a TTY.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "RAM-efficient coding agent TUI with multi-model support and swarm coordination";
    homepage = "https://github.com/smdex/jcode";
    changelog = "https://github.com/smdex/jcode/commit/${finalAttrs.src.rev}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "jcode";
    platforms = platforms.unix;
  };
})
