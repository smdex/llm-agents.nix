{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  pkg-config,
  openssl,
  stdenv,
  versionCheckHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "opendev";
  version = "0.1.9";

  src = fetchFromGitHub {
    owner = "opendev-to";
    repo = "opendev";
    tag = "v${version}";
    hash = "sha256-bBqzf7K7FXWzqcMliyKeo4yMFF/ystSU7AgSqxwA8Ko=";
  };

  cargoHash = "sha256-8w9Mk/G82hgpp5KrkowWxLKTLn1katRcQfPhrmS1SE8=";

  cargoBuildFlags = [
    "--package"
    "opendev-cli"
  ];
  cargoTestFlags = cargoBuildFlags;

  # Tests require network access
  doCheck = false;

  env = {
    OPENSSL_NO_VENDOR = "1";
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ pkg-config ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ openssl ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Open-Source Coding Agent in the terminal";
    homepage = "https://github.com/opendev-to/opendev";
    changelog = "https://github.com/opendev-to/opendev/releases/tag/v${version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "opendev";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
