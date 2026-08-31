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
  version = "0.4.37";
  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    tag = "v${version}";
    hash = "sha256-/0XVt2xxQPbD6cjudQEq68O53zMuPLkEa0hT8hPsth0=";
  };

  pnpm = pnpm_10;
  pnpmDeps = fetchPnpmDeps {
    inherit
      pname
      version
      src
      pnpm
      ;
    hash = "sha256-Sfc1ep72jG0KoaSjr9EDfGkX2Ce5U7vkv7uX+h3m25E=";
    fetcherVersion = 3;
  };
  electron = electron_41;

  # Deterministic prune of the workspace install down to the runtime
  # closure of the built main/preload bundles (see the script header for
  # why `pnpm deploy` is not used).
  pruneRuntimeDeps = ./prune-runtime-deps.mjs;

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

    pnpm --filter @multica/desktop build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app=$out/share/${pname}
    desktop=$app/apps/desktop
    mkdir -p "$desktop" "$out/bin"

    # Runtime payloads only. electron-vite bundles the renderer fully; the
    # main/preload bundles keep their dependencies external, resolved from a
    # pruned node_modules installed next to them.
    cp -a apps/desktop/out "$desktop/"

    # bundle-cli.mjs wipes resources/bin when Go is unavailable, so the CLI
    # symlink can only be planted after the build step above.
    mkdir -p apps/desktop/resources/bin
    ln -s ${multica}/bin/multica apps/desktop/resources/bin/multica
    cp -a apps/desktop/resources "$desktop/"
    # Started directly on the bundle, app.getAppPath() is out/main; the
    # daemon manager resolves the bundled CLI as <appPath>/resources/bin.
    ln -s ../../resources "$desktop/out/main/resources"

    node ${pruneRuntimeDeps} . apps/desktop/out \
      "$desktop/node_modules"

    install -Dm644 apps/desktop/build/icon.png \
      $out/share/icons/hicolor/512x512/apps/multica.png

    makeWrapper ${electron}/bin/electron $out/bin/multica-desktop \
      --add-flags "$desktop/out/main/index.js" \
      --add-flags "--no-sandbox" \
      --add-flags ''${NIXOS_OZONE_WL:+''${WAYLAND_DISPLAY:+--ozone-platform-hint=auto --enable-features=WaylandWindowDecorations}} \
      --inherit-argv0

    copyDesktopItems
    runHook postInstall
  '';

  doInstallCheck = true;
  # Plain node cannot load the electron builtin, but require.resolve of the
  # bundled externals from the installed app dir proves the pruned runtime
  # node_modules is self-contained.
  installCheckPhase = ''
    runHook preInstallCheck
    cd $out/share/${pname}/apps/desktop
    for dep in @electron-toolkit/utils @electron-toolkit/preload electron-updater fix-path; do
      node -e 'require.resolve(process.argv[1])' "$dep" || {
        echo "error: runtime dependency $dep not resolvable in installed app"
        exit 1
      }
    done
    runHook postInstallCheck
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
