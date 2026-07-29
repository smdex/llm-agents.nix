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
  version = "1.45.0";

  src = fetchFromGitHub {
    owner = "aaif-goose";
    repo = "goose";
    rev = "v1.45.0";
    hash = "sha256-B7SjNAc+EmRtKf6Lp7OtjKARo+OWd6A6tRkp7VlAkDU=";
  };

  sourceRoot = "${finalAttrs.src.name}/ui";
  postPatch = ''
    cat > pnpm-workspace.yaml <<'EOF'
    packages:
      - sdk
      - text
    overrides:
      react: ^19.2.4
      react-dom: ^19.2.4
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
    hash = "sha256-DTW6YmTvK95Bb8KCPC8iRfy0xCrpMdhjPGpIO3UY384=";
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
    cp -rL node_modules sdk text/package.json text/dist $out/lib/goose-tui/
    # pnpm keeps the UI's runtime dependencies in the text workspace. Merge
    # those links into the runtime root so dist/tui.js can resolve react and
    # the other workspace-local dependencies after installation.
    if [ -d text/node_modules ]; then
      cp -rL text/node_modules/. $out/lib/goose-tui/node_modules/
    fi
    if [ -d node_modules/.pnpm/node_modules ]; then
      cp -rL node_modules/.pnpm/node_modules/. $out/lib/goose-tui/node_modules/
    fi
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
  preVersionCheck = ''
    version="$(node -p "require('./text/package.json').version")"
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "TypeScript terminal UI for Goose";
    homepage = "https://github.com/aaif-goose/goose/tree/main/ui/text";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v1.45.0";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "goose-tui";
    platforms = platforms.all;
  };
})
