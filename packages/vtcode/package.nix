{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  callPackage,
  makeRustPlatform,
  cargo,
  formatelf,
  pkg-config,
  openssl,
  aws-lc,
  rust-jemalloc-sys,
  sqlite,
  libiconv,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  toolchain = callPackage ./rust-toolchain.nix { };
  rustPlatform = makeRustPlatform {
    rustc = toolchain;
    inherit cargo;
  };
in
rustPlatform.buildRustPackage rec {
  pname = "vtcode";
  version = "0.183.1";

  src = fetchFromGitHub {
    owner = "vinhnx";
    repo = "vtcode";
    tag = version;
    hash = "sha256-zQ1P6/9a3oQuXOA85P91FycM1ORWkPI9Hm4zkr2jjg0=";
  };

  cargoHash = "sha256-M4cfplB0kiSBOMQRNNoHHzzZBa5rt0B774W+9b1zEFI=";

  cargoBuildFlags = [
    "--bin"
    "vtcode"
  ];

  nativeBuildInputs = [ pkg-config ] ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = [
    openssl
    aws-lc
    rust-jemalloc-sys
    sqlite
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  preBuild = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'codegen-units = 1' 'codegen-units = 16' \
      --replace-fail 'lto = true' 'lto = "thin"'
  '';

  env = {
    CARGO_BUILD_JOBS = "4";
    JEMALLOC_OVERRIDE = "${lib.getLib rust-jemalloc-sys}/lib/libjemalloc${stdenv.hostPlatform.extensions.sharedLibrary}";
  };

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
    platforms = toolchain.meta.platforms;
    mainProgram = "vtcode";
  };
}
