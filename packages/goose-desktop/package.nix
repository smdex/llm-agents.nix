{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  fetchurl,
  runCommand,
  makeWrapper,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  electron_41,
  goose-cli,
}:

let
  pnpm = pnpm_10;
  electron = electron_41;
  electronVersion = "41.0.0";
  electronZip = fetchurl {
    url = "https://github.com/electron/electron/releases/download/v${electronVersion}/electron-v${electronVersion}-linux-x64.zip";
    hash = "sha256-oo1atjj6BlhTyA1fJ+qdfsf4Yh2SQiAPdHeYxe0xk9Q=";
  };
  electronZipDir = runCommand "electron-${electronVersion}-zip-dir" { } ''
    mkdir -p $out
    ln -s ${electronZip} $out/electron-v${electronVersion}-linux-x64.zip
  '';
in
stdenv.mkDerivation (finalAttrs: {
  pname = "goose-desktop";
  version = "1.47.0";

  src = fetchFromGitHub {
    owner = "aaif-goose";
    repo = "goose";
    tag = "v${finalAttrs.version}";
    hash = "sha256-+sowkBtUbpBPAgi1Tn1WSgIac2yzCWsXcsh96Pp5VSY=";
  };

  sourceRoot = "${finalAttrs.src.name}/ui";
  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    sourceRoot = "${finalAttrs.src.name}/ui";
    inherit pnpm;
    fetcherVersion = 3;
    hash = "sha256-suVaAsK8bzsb2nNbvlhb/lMjs3Q2fiKRo3TSpome6tI=";
  };

  postPatch = ''
    substituteInPlace desktop/forge.config.ts \
      --replace-fail 'rebuildConfig: {},' 'rebuildConfig: { onlyModules: [] },' \
      --replace-fail 'packagerConfig: cfg,' 'packagerConfig: { ...cfg, electronZipDir: "${electronZipDir}" },'
  '';

  nativeBuildInputs = [
    makeWrapper
    nodejs
    pnpm
    pnpmConfigHook
  ];

  # electron-forge's packager is given the exact npm-pinned Electron archive
  # from the Nix store. This avoids @electron/get network access in the build
  # sandbox. The final application runtime is the Nix Electron distribution.
  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    npm_config_runtime = "electron";
    npm_config_target = electronVersion;
    npm_config_nodedir = electron.headers;
    ELECTRON_SKIP_REBUILD = "1";
  };

  dontStrip = true;

  buildPhase = ''
    runHook preBuild

    set +e
    pnpm --filter @aaif/goose-sdk exec tsc --pretty false --diagnostics
    tscStatus=$?
    echo "SDK TypeScript status: $tscStatus"
    set -e
    test "$tscStatus" -eq 0

    # Forge's extraResource rule copies src/bin into resources/bin. Keep the
    # source-built ACP executable as a store symlink; the packaged app uses
    # this exact path for `goose serve`.
    mkdir -p desktop/src/bin
    rm -f desktop/src/bin/goose
    ln -s ${lib.getExe goose-cli} desktop/src/bin/goose
    test -L desktop/src/bin/goose
    test "$(realpath desktop/src/bin/goose)" = "${lib.getExe goose-cli}"
    echo "Staged Goose ACP binary: $(realpath desktop/src/bin/goose)"

    # The electron npm package is present in the offline pnpm tree, but its
    # postinstall cannot download a runtime. Give it the Nix runtime path so
    # Forge can load the package while its packager uses electronZipDir above.
    electronPackage=node_modules/electron
    echo "Electron package: $electronPackage"
    test -e "$electronPackage"
    rm -rf "$electronPackage/dist"
    mkdir -p "$electronPackage/dist"
    ln -s ${electron}/bin/electron "$electronPackage/dist/electron"
    printf 'electron\n' > "$electronPackage/path.txt"

    cd desktop
    pnpm run i18n:compile
    pnpm exec electron-forge package --platform=linux --arch=x64
    cd ..

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    appDir=$(find desktop/out -mindepth 1 -maxdepth 1 -type d -name 'Goose-linux-*' | head -1)
    test -n "$appDir"
    mkdir -p $out/libexec/goose-desktop $out/bin
    cp -a "$appDir/." $out/libexec/goose-desktop/
    cp -a ${electron.dist}/. $out/libexec/goose-desktop/

    install -Dm644 desktop/src/images/icon.png \
      $out/share/icons/hicolor/512x512/apps/goose-desktop.png
    makeWrapper $out/libexec/goose-desktop/Goose $out/bin/goose-desktop \
      --add-flags "--no-sandbox"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/goose-desktop
    test -x $out/libexec/goose-desktop/Goose
    test -f $out/libexec/goose-desktop/resources/app.asar
    test -L $out/libexec/goose-desktop/resources/bin/goose
    test "$(realpath $out/libexec/goose-desktop/resources/bin/goose)" = "${lib.getExe goose-cli}"
    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Legacy Electron desktop app for Goose, a local extensible AI agent";
    homepage = "https://github.com/aaif-goose/goose";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "goose-desktop";
    platforms = [ "x86_64-linux" ];
  };
})
