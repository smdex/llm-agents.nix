{
  lib,
  stdenv,
  flake,
  fetchurl,
  autoPatchelfHook,
  makeWrapper,
  binutils,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libxkbcommon,
  mesa,
  nspr,
  nss,
  pango,
  zstd,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxrandr,
  libxrender,
  libxtst,
  libxcb,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "goose-desktop";
  version = "1.39.0";

  src = fetchurl {
    url = "https://github.com/aaif-goose/goose/releases/download/v${finalAttrs.version}/goose_${finalAttrs.version}_amd64.deb";
    hash = "sha256-nn7G4+84m55k8KXGHVnBUsfD8wuI4ZnAmjhVHM6Y8j4=";
  };

  nativeBuildInputs = [
    autoPatchelfHook
    binutils
    makeWrapper
    zstd
  ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libdrm
    libgbm
    libxkbcommon
    mesa
    nspr
    nss
    pango
    stdenv.cc.cc.lib
    libx11
    libxscrnsaver
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
    libxcb
  ];

  runtimeDependencies = finalAttrs.buildInputs;

  unpackPhase = ''
    runHook preUnpack
    ar x $src
    tar --no-same-owner --no-same-permissions -xf data.tar.*
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib $out/share
    cp -r usr/lib/goose $out/lib/goose
    if [ -d usr/share/applications ]; then
      mkdir -p $out/share/applications
      cp -r usr/share/applications/. $out/share/applications/
      substituteInPlace $out/share/applications/goose.desktop \
        --replace-fail "/usr/lib/goose/Goose" "goose-desktop" \
        --replace-fail "/usr/share/pixmaps/goose.png" "goose-desktop"
    fi
    if [ -f usr/share/pixmaps/goose.png ]; then
      install -Dm644 usr/share/pixmaps/goose.png \
        $out/share/icons/hicolor/512x512/apps/goose-desktop.png
    fi

    makeWrapper $out/lib/goose/Goose $out/bin/goose-desktop \
      --add-flags "--no-sandbox"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/goose-desktop
    test -f $out/lib/goose/resources/app.asar
    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Legacy Electron desktop app for Goose, a local extensible AI agent";
    homepage = "https://github.com/aaif-goose/goose";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "goose-desktop";
    platforms = [ "x86_64-linux" ];
  };
})
