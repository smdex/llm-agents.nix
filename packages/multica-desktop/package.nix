{
  lib,
  flake,
  stdenvNoCC,
  fetchurl,
  appimageTools,
  autoPatchelfHook,
  copyDesktopItems,
  makeDesktopItem,
  makeWrapper,
  alsa-lib,
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  dbus-glib,
  expat,
  gcc-unwrapped,
  glib,
  gtk2,
  gtk3,
  libdbusmenu-gtk2,
  libdrm,
  libgbm,
  libX11,
  libxcb,
  libXcomposite,
  libXcursor,
  libXdamage,
  libXext,
  libXfixes,
  libXrandr,
  libxkbcommon,
  nspr,
  nss,
  pango,
  systemdLibs,
  libglvnd,
  libnotify,
  libpulseaudio,
  libsecret,
  libayatana-appindicator,
  pipewire,
  wayland,
  xdg-utils,
  adwaita-icon-theme,
  gsettings-desktop-schemas,
}:

let
  pname = "multica-desktop";
  version = "0.4.0";

  platform = stdenvNoCC.hostPlatform.system;
  platformInfo =
    {
      x86_64-linux = {
        arch = "x86_64";
        hash = "sha256-3q4Ejo3OV+cpBkyZB8GK1uMIICy+Wd3QDPSCD529NBs=";
      };
      aarch64-linux = {
        arch = "arm64";
        hash = "sha256-/GaBx4+CqsN84/7dgIeEJrWvTl7LAISpkqLwZ7pko6Q=";
      };
    }
    .${platform} or (throw "${pname}: unsupported system ${platform}");

  src = fetchurl {
    url = "https://github.com/multica-ai/multica/releases/download/v${version}/multica-desktop-${version}-linux-${platformInfo.arch}.AppImage";
    inherit (platformInfo) hash;
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };

  desktopItem = makeDesktopItem {
    name = pname;
    desktopName = "Multica";
    genericName = "Multica Desktop Client";
    comment = "Native desktop client for the Multica platform";
    exec = "multica-desktop %U";
    icon = "multica";
    categories = [ "Utility" ];
    startupWMClass = "Multica";
    mimeTypes = [ "x-scheme-handler/multica" ];
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    makeWrapper
  ];

  # Direct Electron links discovered from the upstream AppImage.
  buildInputs = [
    adwaita-icon-theme
    alsa-lib
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    dbus-glib
    expat
    gcc-unwrapped.lib
    glib
    gsettings-desktop-schemas
    gtk2
    gtk3
    libdbusmenu-gtk2
    libdrm
    libgbm
    libX11
    libxcb
    libXcomposite
    libXcursor
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
    libayatana-appindicator
    libglvnd
    libnotify
    libpulseaudio
    libsecret
    pipewire
    wayland
  ];

  desktopItems = [ desktopItem ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/multica-desktop $out/share/icons
    cp -a ${appimageContents}/. $out/lib/multica-desktop/
    chmod -R u+w $out/lib/multica-desktop

    # The desktop app bundles the static Go CLI. Expose it as a stable Nix
    # program so daemons and systemd units never download a second copy.
    install -Dm755 \
      $out/lib/multica-desktop/resources/app.asar.unpacked/resources/bin/multica \
      $out/bin/multica

    # Nix owns updates. Removing this release's updater config prevents the
    # bundled electron-updater from downloading a second, unmanaged copy.
    rm -f $out/lib/multica-desktop/resources/app-update.yml

    # Retain upstream-provided icon sizes for normal desktop-shell lookup.
    cp -a $out/lib/multica-desktop/usr/share/icons $out/share/

    makeWrapper $out/lib/multica-desktop/multica $out/bin/multica-desktop \
      --set APPDIR $out/lib/multica-desktop \
      --prefix LD_LIBRARY_PATH : $out/lib/multica-desktop \
      --suffix PATH : ${lib.makeBinPath [ xdg-utils ]} \
      --prefix XDG_DATA_DIRS : "$XDG_ICON_DIRS:$GSETTINGS_SCHEMAS_PATH" \
      --run 'if [ -z "''${ELECTRON_RUN_AS_NODE:-}" ]; then
        set -- --disable-setuid-sandbox "$@"
        if [ -n "''${NIXOS_OZONE_WL:-}" ] && [ -n "''${WAYLAND_DISPLAY:-}" ]; then
          set -- --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations --enable-wayland-ime=true "$@"
        fi
      fi'


    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    ELECTRON_RUN_AS_NODE=1 $out/bin/multica-desktop -e \
      "console.log(require('$out/lib/multica-desktop/resources/app.asar/package.json').version)" \
      | grep -F '${version}'

    runHook postInstallCheck
  '';

  passthru = {
    category = "AI Assistants";
    selfHostedConfig = {
      path = "~/.multica/desktop.json";
      example = {
        schemaVersion = 1;
        apiUrl = "https://multica.mtech.zt";
        wsUrl = "wss://multica.mtech.zt/ws";
        appUrl = "https://multica.mtech.zt";
      };
    };
  };

  meta = with lib; {
    description = "Native desktop client for the Multica platform";
    homepage = "https://github.com/multica-ai/multica";
    changelog = "https://github.com/multica-ai/multica/releases/tag/v${version}";
    # Upstream marks the desktop application UNLICENSED and ships a modified
    # Apache-2.0 grant, so it must not be represented as Apache-2.0.
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "multica-desktop";
  };
}
