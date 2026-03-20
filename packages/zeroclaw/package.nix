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
  version = "0.5.1";

  src = fetchFromGitHub {
    owner = "zeroclaw-labs";
    repo = "zeroclaw";
    tag = "v${version}";
    hash = "sha256-5P+TjAf7i0oUxBCyBtagrmIHPXW2iZ6620PNxVYYjlQ=";
  };

  cargoHash = "sha256-tpgeRLWyye43fuzw2MRevQx8YKEbyOnIgLzjg8EzwCg=";

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
