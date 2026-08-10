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
  openssl,
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
  webkitgtk_4_1,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "goose2";
  version = "0.1.0";
  upstreamTag = "v2.0.0-rc-04-27-0";

  src = fetchurl {
    url = "https://github.com/aaif-goose/goose/releases/download/${finalAttrs.upstreamTag}/Goose_${finalAttrs.version}_amd64.deb";
    hash = "sha256-OgvRgJjayo2HVj4o4ZACOxoPZ8czky3lJqPbp1fPP8E=";
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
    openssl
    pango
    stdenv.cc.cc.lib
    webkitgtk_4_1
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
    install -Dm755 usr/bin/goose-tauri $out/lib/goose2/goose-tauri
    if [ -f usr/bin/goose ]; then install -Dm755 usr/bin/goose $out/lib/goose2/goose; fi
    if [ -d usr/share/applications ]; then
      mkdir -p $out/share/applications
      cp -r usr/share/applications/. $out/share/applications/
      for desktopFile in $out/share/applications/*.desktop; do
        substituteInPlace "$desktopFile" \
          --replace-warn "/usr/bin/goose" "goose2" \
          --replace-warn "goose-tauri" "goose2" \
          --replace-warn "Goose" "Goose 2"
      done
    fi
    if [ -f usr/share/pixmaps/goose.png ]; then
      install -Dm644 usr/share/pixmaps/goose.png \
        $out/share/icons/hicolor/512x512/apps/goose2.png
    fi

    makeWrapper $out/lib/goose2/goose-tauri $out/bin/goose2

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -x $out/bin/goose2
    test -x $out/lib/goose2/goose-tauri
    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Goose 2 Tauri desktop app for Goose, a local extensible AI agent";
    homepage = "https://github.com/aaif-goose/goose";
    changelog = "https://github.com/aaif-goose/goose/releases/tag/${finalAttrs.upstreamTag}";
    license = lib.licenses.asl20;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "goose2";
    platforms = [ "x86_64-linux" ];
  };
})
