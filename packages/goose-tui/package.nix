{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  versionCheckHook,
  versionCheckHomeHook,
  goose-cli,
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
    tag = "v${finalAttrs.version}";
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
    # Preserve pnpm's symlink graph: flattening its hoisted dependencies can
    # pair CommonJS packages with incompatible ESM dependency versions.
    cp -rP node_modules sdk text $out/lib/goose-tui/
    # Keep the shared Goose executable as a store link instead of copying it
    # into the TUI output.
    ln -s ${lib.getExe goose-cli} $out/lib/goose-tui/goose
    makeWrapper ${nodejs}/bin/node $out/bin/goose-tui \
      --add-flags "$out/lib/goose-tui/text/dist/tui.js" \
      --set-default GOOSE_BINARY $out/lib/goose-tui/goose
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
    test -L $out/lib/goose-tui/goose
    test "$(realpath $out/lib/goose-tui/goose)" = "${lib.getExe goose-cli}"
    version="$(node -p "require('./text/package.json').version")"
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "TypeScript terminal UI for Goose";
    homepage = "https://github.com/aaif-goose/goose/tree/main/ui/text";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v${finalAttrs.version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "goose-tui";
    # Its Nix-native Goose ACP server supports only the platforms with a
    # corresponding prebuilt librusty_v8 archive.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
})
