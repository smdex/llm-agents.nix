{
  lib,
  flake,
  platformSource,
  mkUpdater,
  stdenvNoCC,
  bintools,
  formatelf,
  makeWrapper,
  zstd,

  # DT_NEEDED by the Chromium binary, chromedriver and the crashpad handler.
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  gcc-unwrapped,
  glib,
  gtk3,
  libdrm,
  libgbm,
  libX11,
  libxcb,
  libXcomposite,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxkbcommon,
  nspr,
  nss,
  pango,

  # libs-only build of systemd to avoid pulling the whole systemd closure
  systemdLibs,

  # dlopen()ed by Chromium at runtime; autoPatchelf puts their lib dirs on
  # the RUNPATH anyway because they are buildInputs.
  libsecret,
  libnotify,
  libpulseaudio,
  pipewire,
  wayland,

  # The bundled ANGLE libEGL.so dlopens the native libEGL.so.1 (libglvnd).
  libglvnd,

  # For XDG_ICON_DIRS and GSETTINGS_SCHEMAS_PATH.
  adwaita-icon-theme,
  gsettings-desktop-schemas,

  xdg-utils,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "amd64";
    };
    urlTemplate = "https://github.com/browseros-ai/BrowserOS/releases/download/browserclaw/v{version}/BrowserOS_neo_v{version}_{platform}.deb";
  };
in
stdenvNoCC.mkDerivation {
  pname = "browseros-neo";
  inherit (source) version src;

  nativeBuildInputs = [
    formatelf
    makeWrapper
    zstd # the deb's data.tar.zst
  ];

  buildInputs = [
    adwaita-icon-theme
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    gcc-unwrapped.lib
    glib
    gsettings-desktop-schemas
    gtk3
    libdrm
    libgbm
    libX11
    libxcb
    libXcomposite
    libXdamage
    libXext
    libXfixes
    libXrandr
    libxkbcommon
    nspr
    nss
    pango
    systemdLibs
  ];

  runtimeDependencies = [
    libglvnd
    libnotify
    libpulseaudio
    libsecret
    pipewire
    wayland
  ];

  # The optional Qt UI-toolkit shims are dlopen()ed only with
  # --ui-toolkit=qt5/qt6; pull no Qt into the closure for a rare flag.
  autoPatchelfIgnoreMissingDeps = [
    "libQt5Core.so.5"
    "libQt5Gui.so.5"
    "libQt5Widgets.so.5"
    "libQt6Core.so.6"
    "libQt6Gui.so.6"
    "libQt6Widgets.so.6"
  ];

  # The bundled BrowserClawServer agent sidecar is bun-compiled: stripping
  # would corrupt the bytecode payload at the end of the binary.
  dontStrip = true;

  unpackPhase = ''
    runHook preUnpack
    ${lib.getExe' bintools "ar"} x $src
    tar --zstd -xf data.tar.zst
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    # Keep upstream's layout so resources, libraries and the sidecar resolve
    # relative to the main binary.
    mkdir -p $out/lib $out/bin $out/share
    cp -a usr/lib/browserclaw $out/lib/browserclaw
    cp -a usr/share/icons $out/share/icons
    cp -a usr/share/metainfo $out/share/metainfo

    # chrome-sandbox needs setuid root, which a store path can never have.
    # Chromium falls back to user namespaces, as for every other prebuilt
    # Chromium/Electron app packaged here.
    rm -f $out/lib/browserclaw/chrome_sandbox

    # Reuse upstream's desktop entry (it carries the full web mime list);
    # just repoint the exec at our wrapper name.
    install -Dm644 usr/share/applications/browserclaw.desktop $out/share/applications/browseros-neo.desktop
    substituteInPlace $out/share/applications/browseros-neo.desktop \
      --replace-fail "/usr/bin/browserclaw" "browseros-neo"

    makeWrapper "$out/lib/browserclaw/browserclaw" "$out/bin/browseros-neo" \
      --suffix PATH : "${lib.makeBinPath [ xdg-utils ]}" \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --add-flags "\''${NIXOS_OZONE_WL:+\''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true}}"

    runHook postInstall
  '';

  passthru = {
    category = "AI Assistants";

    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "text";
          url = "https://api.github.com/repos/browseros-ai/BrowserOS/releases/latest";
          regex = ''"tag_name"\s*:\s*"browserclaw/v([0-9.]+)"'';
        };
      }
    );
  };

  meta = {
    description = "The open source agentic browser";
    longDescription = ''
      BrowserOS is a privacy-focused web browser built on Chromium with a
      built-in AI agent. This is the full browser, repacked from the
      official upstream .deb release.
    '';
    homepage = "https://www.browseros.com/";
    changelog = "https://github.com/browseros-ai/BrowserOS/releases/tag/browserclaw/v${source.version}";
    license = lib.licenses.bsd3;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "browseros-neo";
    platforms = source.platforms;
  };
}
