{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  pnpm = pnpm_10;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "goose-tui";
  version = "0.20.1";

  src = fetchFromGitHub {
    owner = "aaif-goose";
    repo = "goose";
    rev = "v1.37.0";
    hash = "sha256-YEK4cGcSx2ppEtR60x/4wwtJFMDO9jnK5bAo2RW3E64=";
  };

  sourceRoot = "${finalAttrs.src.name}/ui";
  postPatch = ''
    cat > pnpm-workspace.yaml <<'EOF'
    packages:
      - sdk
      - text
    EOF
  '';

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      postPatch
      ;
    sourceRoot = "${finalAttrs.src.name}/ui";
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-xFW9NUN/oR7c7bBwydHksASfPywuIQFP++Y0u7hYTBs=";
  };

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm
    pnpmConfigHook
  ];

  dontStrip = true;
  dontFixup = true;

  buildPhase = ''
    runHook preBuild
    pnpm --filter @aaif/goose-sdk build:ts
    pnpm --filter @aaif/goose build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/{bin,lib/goose-tui}
    cp -r node_modules sdk text/package.json text/dist $out/lib/goose-tui/
    rm -rf $out/lib/goose-tui/node_modules/@aaif/goose-sdk
    mkdir -p $out/lib/goose-tui/node_modules/@aaif
    ln -s ../../sdk $out/lib/goose-tui/node_modules/@aaif/goose-sdk
    makeWrapper ${nodejs}/bin/node $out/bin/goose-tui \
      --add-flags "$out/lib/goose-tui/dist/tui.js"
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgram = "${placeholder "out"}/bin/goose-tui";
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "TypeScript terminal UI for Goose";
    homepage = "https://github.com/aaif-goose/goose/tree/main/ui/text";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v1.37.0";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "goose-tui";
    platforms = platforms.all;
  };
})
