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
  version = "1.0.0-rc.102";

  src = fetchFromGitHub {
    owner = "xerj-org";
    repo = "xerj";
    tag = "v${version}";
    hash = "sha256-hACHohJJ4FCNXP13X16sy7IxiX6KAPi/clp+AIzTNTc=";
  };

  sourceRoot = "source/engine";
  cargoHash = "sha256-SNP9oR3WRsoe26hePiQliiFegyl/i1rADgXPRxnL91w=";

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
  buildInputs = [ openssl ] ++ lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];
  env.OPENSSL_NO_VENDOR = "1";

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
