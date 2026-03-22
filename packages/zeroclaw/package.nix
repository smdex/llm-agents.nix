{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "zeroclaw";
  version = "0.5.6";

  src = fetchFromGitHub {
    owner = "zeroclaw-labs";
    repo = "zeroclaw";
    tag = "v${version}";
    hash = "sha256-xMJA6YEaH39IXAzAxvf04By0nrCcVvy2QOohN/F5dm8=";
  };

  cargoHash = "sha256-uydJYWYSYzeNGUy3T7SaTzJm5N98kMIFzS59fG6KN8A=";

  # Tests require runtime configuration and network access
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Fast, small, and fully autonomous AI assistant infrastructure";
    homepage = "https://github.com/zeroclaw-labs/zeroclaw";
    changelog = "https://github.com/zeroclaw-labs/zeroclaw/releases";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ commandodev ];
    mainProgram = "zeroclaw";
    platforms = lib.platforms.unix;
  };
}
