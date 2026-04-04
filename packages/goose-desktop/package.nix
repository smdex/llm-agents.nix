{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  dpkg,
  makeWrapper,
  alsa-lib,
  atk,
  at-spi2-atk,
  at-spi2-core,
  cairo,
  cups,
  dbus,
  expat,
  gcc-unwrapped,
  glib,
  gtk3,
  libdrm,
  libglvnd,
  libx11,
  libxscrnsaver,
  libxcomposite,
  libxdamage,
  libxext,
  libxfixes,
  libxrandr,
  libxkbcommon,
  libxcb,
  mesa,
  nspr,
  nss,
  pango,
  systemd,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  runtimeLibs = [
    alsa-lib
    atk
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    gcc-unwrapped.lib
    glib
    gtk3
    libdrm
    libglvnd
    libxkbcommon
    mesa
    nspr
    nss
    pango
    systemd
    libx11
    libxscrnsaver
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxrandr
    libxcb
  ];
in
stdenv.mkDerivation {
  pname = "goose-desktop";
  inherit version;

  src = fetchurl {
    url = "https://github.com/aaif-goose/goose/releases/download/v${version}/goose_${version}_amd64.deb";
    hash = hashes.x86_64-linux;
  };

  nativeBuildInputs = [
    autoPatchelfHook
    dpkg
    makeWrapper
  ];

  buildInputs = runtimeLibs;
  runtimeDependencies = runtimeLibs;

  unpackPhase = ''
    runHook preUnpack

    dpkg-deb --fsys-tarfile $src | tar --no-same-owner --no-same-permissions -xf -

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/bin $out/share/applications $out/share/pixmaps
    cp -r usr/lib/goose $out/lib/goose

    makeWrapper $out/lib/goose/Goose $out/bin/goose-desktop \
      --add-flags "--no-sandbox" \
      --set-default ENABLE_DEV_UPDATES false

    install -Dm644 usr/share/pixmaps/goose.png $out/share/pixmaps/goose.png
    install -Dm644 usr/share/applications/goose.desktop $out/share/applications/goose.desktop
    substituteInPlace $out/share/applications/goose.desktop \
      --replace-fail "Exec=/usr/lib/goose/Goose %U" "Exec=$out/bin/goose-desktop %U" \
      --replace-fail "Icon=/usr/share/pixmaps/goose.png" "Icon=$out/share/pixmaps/goose.png"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/goose-desktop"
    test -x "$out/lib/goose/Goose"
    test -f "$out/lib/goose/resources/app.asar"
    test -x "$out/lib/goose/resources/bin/goosed"
    test -f "$out/share/applications/goose.desktop"
    test -f "$out/share/pixmaps/goose.png"
  '';

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Desktop app for Goose - a local, extensible, open source AI agent";
    homepage = "https://github.com/block/goose";
    changelog = "https://github.com/block/goose/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "goose-desktop";
    platforms = [ "x86_64-linux" ];
  };
}
