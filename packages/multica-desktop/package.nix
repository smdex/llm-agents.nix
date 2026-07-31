{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  makeWrapper,
  copyDesktopItems,
  makeDesktopItem,
  nodejs,
  pnpm_10,
  pnpmConfigHook,
  electron_41,
  multica,
  ...
}:

let
  pname = "multica-desktop";
  version = "0.4.16";
  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    tag = "v${version}";
    hash = "sha256-mgC1WxeYyDgfE8gBbwGVQCzT0Y8C6DjKYfUM/2bkHbs=";
  };

  pnpm = pnpm_10;
  pnpmDeps = fetchPnpmDeps {
    inherit
      pname
      version
      src
      pnpm
      ;
    hash = "sha256-AZ6DPUEqVWqHUxHHNVoFQEzuOErNDu1hmRy7s3WvzrQ=";
    fetcherVersion = 3;
  };
  electron = electron_41;

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
stdenv.mkDerivation {
  inherit
    pname
    version
    src
    pnpmDeps
    ;

  nativeBuildInputs = [
    nodejs
    pnpm
    pnpmConfigHook
    makeWrapper
    copyDesktopItems
  ];

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    npm_config_electron_skip_binary_download = "1";
  };

  buildPhase = ''
    runHook preBuild

    # Upstream pins Electron 39; use the maintained nixpkgs major and fail if
    # upstream ever moves beyond the ABI we have selected.
    upstream_electron=$(node -p "require('./apps/desktop/package.json').devDependencies.electron")
    upstream_major=''${upstream_electron#^}
    upstream_major=''${upstream_major%%.*}
    nix_major=${lib.versions.major electron.version}
    if (( upstream_major > nix_major )); then
      echo "error: upstream expects Electron $upstream_electron but we provide ${electron.version}"
      exit 1
    fi

    mkdir -p apps/desktop/resources/bin
    ln -s ${multica}/bin/multica apps/desktop/resources/bin/multica
    pnpm --filter @multica/desktop build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app=$out/share/${pname}
    mkdir -p "$app" "$out/bin"
    # Keep workspace links valid at runtime; pnpm links @multica packages back
    # into the root apps/ and packages/ directories.
    cp -a apps packages "$app/"
    rm -rf "$app/apps/desktop/out" "$app/apps/desktop/resources"
    cp -a apps/desktop/out apps/desktop/resources "$app/apps/desktop/"
    cp -a node_modules "$app/node_modules"

    install -Dm644 apps/desktop/build/icon.png \
      $out/share/icons/hicolor/512x512/apps/multica.png

    makeWrapper ${electron}/bin/electron $out/bin/multica-desktop \
      --add-flags "$app/apps/desktop/out/main/index.js" \
      --add-flags "--no-sandbox" \
      --add-flags ''${NIXOS_OZONE_WL:+''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}} \
      --inherit-argv0

    copyDesktopItems
    runHook postInstall
  '';

  desktopItems = [ desktopItem ];

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
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = platforms.linux;
    mainProgram = "multica-desktop";
  };
}
