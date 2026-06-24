{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  openssl,
  stdenv,
  libiconv,
  versionCheckHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "tokscale";
  version = "4.0.2";

  src = fetchFromGitHub {
    owner = "junhoyeo";
    repo = "tokscale";
    rev = "v${version}";
    hash = "sha256-iX5X9T5Kc51VnQF1+vBXXXivcYID7ErF5ZSfj31zNv4=";
  };

  cargoHash = "sha256-qwNT66/H1FI/XIRndmccYI4cx9DOQUIODuOdWqzY0io=";

  # Use nixpkgs OpenSSL instead of building vendored OpenSSL from source.
  postPatch = ''
    substituteInPlace Cargo.toml \
      --replace-fail 'native-tls-vendored' 'native-tls' \
      --replace-fail 'lto = true' 'lto = false' \
      --replace-fail 'codegen-units = 1' 'codegen-units = 16'
  '';

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ openssl ] ++ lib.optionals stdenv.hostPlatform.isDarwin [ libiconv ];

  # Upstream CLI tests require network access for live pricing data and have
  # local-timezone-sensitive date boundary assertions.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Usage Analytics";

  meta = with lib; {
    description = "CLI and TUI for AI token usage analytics";
    homepage = "https://github.com/junhoyeo/tokscale";
    changelog = "https://github.com/junhoyeo/tokscale/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "tokscale";
    platforms = platforms.all;
  };
}
