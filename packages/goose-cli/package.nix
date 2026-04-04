{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  gcc-unwrapped,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  platformAssets = {
    x86_64-linux = "goose-x86_64-unknown-linux-gnu.tar.bz2";
    aarch64-linux = "goose-aarch64-unknown-linux-gnu.tar.bz2";
    x86_64-darwin = "goose-x86_64-apple-darwin.tar.bz2";
    aarch64-darwin = "goose-aarch64-apple-darwin.tar.bz2";
  };

  platform = stdenv.hostPlatform.system;
  asset = platformAssets.${platform} or (throw "Unsupported system: ${platform}");
in
stdenv.mkDerivation {
  pname = "goose-cli";
  inherit version;

  src = fetchurl {
    url = "https://github.com/aaif-goose/goose/releases/download/v${version}/${asset}";
    hash = hashes.${platform} or (throw "Missing goose-cli hash for platform ${platform}");
  };

  sourceRoot = ".";

  dontStrip = stdenv.hostPlatform.isDarwin;

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ gcc-unwrapped.lib ];

  installPhase = ''
    runHook preInstall

    install -Dm755 goose $out/bin/goose

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "CLI for Goose - a local, extensible, open source AI agent that automates engineering tasks";
    homepage = "https://github.com/block/goose";
    changelog = "https://github.com/block/goose/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "goose";
    platforms = builtins.attrNames platformAssets;
  };
}
