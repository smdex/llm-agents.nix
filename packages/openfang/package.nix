{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  versionCheckHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "openfang";
  version = "0.5.5";

  src = fetchFromGitHub {
    owner = "RightNow-AI";
    repo = "openfang";
    tag = "v${version}";
    hash = "sha256-4urylh7EI1yY9Qrtvg/AFgnRxHuQJIs/W24nLZ38tjc=";
  };

  cargoHash = "sha256-QkdfZNDGvj3yYOlqhGx/2UyO8hpydqf2CRVTOYFhmmU=";

  # Build only the CLI crate
  buildAndTestSubdir = "crates/openfang-cli";

  nativeBuildInputs = [ pkg-config ];

  buildInputs = [ openssl ];

  # Tests require network access and external dependencies
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Open-source Agent Operating System built in Rust";
    homepage = "https://openfang.sh";
    changelog = "https://github.com/RightNow-AI/openfang/releases/tag/v${version}";
    downloadPage = "https://github.com/RightNow-AI/openfang/releases";
    license = with licenses; [
      asl20
      mit
    ];
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ ];
    mainProgram = "openfang";
    platforms = platforms.unix;
  };
}
