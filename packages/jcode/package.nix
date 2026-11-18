{
  lib,
  stdenv,
  flake,
  rustPlatform,
  fetchFromGitHub,
  aws-lc,
  pkg-config,
  openssl,
  oniguruma,
  rust-jemalloc-sys,
  sqlite,
  zstd,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "jcode";
  version = "0.99.2-smdex.14";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "jcode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-eiQMjSTfTKRvTgoJ5dw6Ze7y7NdLukDUBkdcTCwvbLY=";
  };

  cargoHash = "sha256-8red3XwZuLxfdbs05TxIzs6dZ1l/IIXK4yHjcjQFSj8=";

  # .cargo/config.toml caps builds at 4 jobs; let Nix parallelism decide.
  postPatch = ''
    rm .cargo/config.toml
  '';

  nativeBuildInputs = [ pkg-config ];

  # Native AWS-LC pkg-config modules coexist with native-tls's OpenSSL.
  buildInputs = [
    aws-lc
    openssl
    oniguruma
    rust-jemalloc-sys
    sqlite
    zstd
  ];

  # Archives lack git metadata; preserve the verified fork version and revision.
  env = {
    JEMALLOC_OVERRIDE = "${lib.getLib rust-jemalloc-sys}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
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
