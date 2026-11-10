{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  git,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "xerj";
  version = "1.0.0-rc.100";

  src = fetchFromGitHub {
    owner = "xerj-org";
    repo = "xerj";
    tag = "v${version}";
    hash = "sha256-vtO+HFiBvzTmZrNcx9oMTfCGIpBnQYtVoVTHEY4HEmE=";
  };

  sourceRoot = "source/engine";
  cargoHash = "sha256-8WKumTxOQnr8tO2AaV1KpNOcI1I9+CwH4TTSqpt78yM=";

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
  ];
  buildInputs = [ openssl ];
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
