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
  version = "0.181.5";

  src = fetchFromGitHub {
    owner = "vinhnx";
    repo = "vtcode";
    tag = version;
    hash = "sha256-wPn3xHutTDtNgtLKsEeqWWTLTDuy8mNISY7ZEppfwaM=";
  };

  cargoHash = "sha256-4+8pBlog8vAdWkFgo1HpQhEKhTs92RAtlU6Y72mAA9o=";

  cargoBuildFlags = [
    "--bin"
    "vtcode"
  ];

  nativeBuildInputs = [ pkg-config ] ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

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
    platforms = toolchain.meta.platforms;
    mainProgram = "vtcode";
  };
}
