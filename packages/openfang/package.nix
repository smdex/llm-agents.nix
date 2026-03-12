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
  version = "0.3.48";

  src = fetchFromGitHub {
    owner = "RightNow-AI";
    repo = "openfang";
    tag = "v${version}";
    hash = "sha256-QNt44ITlYRsKhvTggxl30+fd/U5AOd7Nt1DI54hcPQE=";
  };

  cargoHash = "sha256-JRlaXc7nj7/RqAPysqtY4FvpE4XAeWuBN9u/2Czny8Y=";

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
