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
  version = "0.4.9";

  src = fetchFromGitHub {
    owner = "RightNow-AI";
    repo = "openfang";
    tag = "v${version}";
    hash = "sha256-/3Kn2yRLbAdIydt4Mw4ayPj0A00geyp5siPr2A/RZpc=";
  };

  cargoHash = "sha256-xVRTj/gEXxrZeUT1Eb7e6/5aYJPzL6zJa8B+NDciPXI=";

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
