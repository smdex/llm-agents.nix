{
  lib,
  flake,
  stdenv,
  callPackage,
  makeRustPlatform,
  cargo,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  sqlite,
  zstd,
  rust-jemalloc-sys,
  git,
  makeWrapper,
  formatelf,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  # candle-core fails llvm.x86.avx512.vpdpbusd.512 intrinsic signature check under
  # nixpkgs Rust/LLVM21 on x86_64-linux; build that platform with the vtcode-pinned
  # rust1.99.1 (LLVM22) toolchain. Other platforms keep the default rustPlatform.
  # The pinned rustc is not the nixpkgs-wrapped rustc, so runtime rpaths are
  # missing; formatelf fixes them on Linux using the declared runtime libraries.
  rustPlatform' =
    if stdenv.hostPlatform.isx86_64 && stdenv.hostPlatform.isLinux then
      makeRustPlatform {
        rustc = callPackage ../vtcode/rust-toolchain.nix { };
        inherit cargo;
      }
    else
      rustPlatform;
in
rustPlatform'.buildRustPackage rec {
  pname = "xerj";
  version = "1.0.0-rc.104";

  src = fetchFromGitHub {
    owner = "xerj-org";
    repo = "xerj";
    tag = "v${version}";
    hash = "sha256-E2kVEgEVU0bxl5U1NXdzJWwLtMjAIheIQ8W+c6cITEo=";
  };

  sourceRoot = "source/engine";
  cargoHash = "sha256-b7C0CNREtye+423qYAUe85ZJjJ1FT/QCM9VwskK5eOE=";

  cargoBuildFlags = [
    "-p"
    "xerj-server"
  ];
  # Test the CLI without building the full multi-process integration suite.
  cargoTestFlags = [
    "-p"
    "xerj-server"
    "--bin"
    "xerj"
  ];

  nativeBuildInputs = [
    pkg-config
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];
  # rc.104 vendored zstd-sys 2.1.2 needs system libzstd via pkg-config, like jcode;
  # rusqlite's libsqlite3-sys links system -lsqlite3 under the same hook.
  buildInputs = [
    openssl
    sqlite
    zstd
    rust-jemalloc-sys
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
  env.OPENSSL_NO_VENDOR = "1";
  # The cargo setup hook's JEMALLOC_OVERRIDE sentinel must point at the real
  # prefixed allocator for the vendored tikv-jemalloc-sys, like jcode/vtcode.
  env.JEMALLOC_OVERRIDE = "${lib.getLib rust-jemalloc-sys}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
  # The test binary links shared libs from buildInputs (jemalloc, zstd, sqlite,
  # openssl) but runs before install-time rpath fixes; point the loader at every
  # declared runtime library dir at once and record what the ELF actually needs.
  preCheck = ''
    export LD_LIBRARY_PATH="${lib.makeLibraryPath buildInputs}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    for elf in target/*/release/xerj target/*/release/deps/xerj-[0-9a-f]*; do
      readelf -d "$elf" 2>/dev/null | grep NEEDED | sed "s|^|DT_NEEDED $elf |" || true
    done
  '';

  postInstall = ''
    wrapProgram $out/bin/xerj --prefix PATH : ${lib.makeBinPath [ git ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Search engine and MCP server for code, documents, and agent memory";
    homepage = "https://github.com/xerj-org/xerj";
    changelog = "https://github.com/xerj-org/xerj/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "xerj";
    platforms = platforms.unix;
  };
}
