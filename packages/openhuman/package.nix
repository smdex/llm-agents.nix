{
  lib,
  flake,
  stdenv,
  runCommand,
  rustPlatform,
  cargo,
  rustc,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_24,
  nodejs_22,
  cmake,
  ninja,
  pkg-config,
  libclang,
  wrapGAppsHook3,
  copyDesktopItems,
  makeDesktopItem,
  versionCheckHomeHook,
  alsa-lib,
  fontconfig,
  glib,
  glib-networking,
  gtk3,
  webkitgtk_4_1,
  libsoup_3,
  openssl,
  libayatana-appindicator,
  libxkbcommon,
  xdotool,
  libx11,
  libxi,
  libxrandr,
  libxtst,
  dbus,
}:

let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);
  pnpm = pnpm_10;

  src = fetchFromGitHub {
    owner = "tinyhumansai";
    repo = "openhuman";
    tag = "v${data.version}";
    hash = data.hash;
  };

  submoduleSource =
    path: pin:
    fetchFromGitHub {
      owner = pin.owner;
      repo = pin.repo;
      name = "openhuman-submodule-${builtins.baseNameOf path}";
      inherit (pin) rev hash;
    };

  # Archives omit gitlinks. The updater records nested source submodules too;
  # sorted paths ensure parents are assembled before their children.
  fullSrc = runCommand "openhuman-${data.version}-src" { } ''
    cp -TR ${src} $out
    chmod -R u+w $out
    ${lib.concatStrings (
      lib.mapAttrsToList (path: pin: ''
        mkdir -p $out/$(dirname ${path})
        cp -TR ${submoduleSource path pin} $out/${path}
        chmod -R u+w $out/${path}
      '') data.submodules
    )}
  '';

  pnpmDeps = fetchPnpmDeps {
    pname = "openhuman";
    inherit src pnpm;
    fetcherVersion = 4;
    hash = data.pnpmDeps;
  };

  # The root CLI workspace and desktop crate deliberately have separate locks.
  cargoDepsCli = rustPlatform.fetchCargoVendor {
    name = "openhuman-${data.version}-cli-deps";
    src = fullSrc;
    hash = data.cargoCliDeps;
  };
  cargoDepsApp = rustPlatform.fetchCargoVendor {
    name = "openhuman-${data.version}-app-deps";
    src = fullSrc;
    cargoRoot = "crates/openhuman-app";
    hash = data.cargoAppDeps;
  };
  compiled = stdenv.mkDerivation (finalAttrs: {
    pname = "openhuman";
    version = data.version;
    src = fullSrc;
    strictDeps = true;
    dontUseCmakeConfigure = true;

    nativeBuildInputs = [
      cargo
      rustc
      cmake
      ninja
      pkg-config
      nodejs_24
      pnpm
      pnpmConfigHook
      libclang
      wrapGAppsHook3
      copyDesktopItems
    ];
    buildInputs = [
      alsa-lib
      fontconfig
      glib
      glib-networking
      gtk3
      webkitgtk_4_1
      libsoup_3
      openssl
      libayatana-appindicator
      libxkbcommon
      xdotool
      libx11
      libxi
      libxrandr
      libxtst
      dbus
    ];

    inherit pnpmDeps;
    env.LIBCLANG_PATH = "${lib.getLib libclang}/lib";

    buildPhase = ''
      runHook preBuild

      # Tauri plugins generate permission schemas in their vendored sources.
      makeCargoHome() {
        local cargo_home="$1" deps="$2" writable="$3"
        cp -R "$deps" "$writable"
        chmod -R u+w "$writable"
        mkdir -p "$cargo_home"
        substitute "$writable/.cargo/config.toml" "$cargo_home/config.toml" \
          --subst-var-by vendor "$writable"
      }
      makeCargoHome "$NIX_BUILD_TOP/cargo-home-cli" "${cargoDepsCli}" "$NIX_BUILD_TOP/vendor-cli"
      makeCargoHome "$NIX_BUILD_TOP/cargo-home-app" "${cargoDepsApp}" "$NIX_BUILD_TOP/vendor-app"
      export CARGO_BUILD_JOBS=$NIX_BUILD_CORES
      export CARGO_NET_OFFLINE=true
      export CARGO_TARGET_DIR="$NIX_BUILD_TOP/target"

      pnpm --filter openhuman-app exec vite build

      export CARGO_HOME="$NIX_BUILD_TOP/cargo-home-cli"
      product_features="$(bash scripts/ci/product-features.sh)"
      cargo build --release --locked --offline \
        --manifest-path "$PWD/Cargo.toml" \
        --package openhuman-cli --bin openhuman-core --features "$product_features"

      # custom-protocol is required for the installed app to load its bundled
      # frontend rather than the development server.
      export CARGO_HOME="$NIX_BUILD_TOP/cargo-home-app"
      cargo build --release --locked --offline \
        --manifest-path "$PWD/crates/openhuman-app/Cargo.toml" \
        --bin OpenHuman --features custom-protocol

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      target="$NIX_BUILD_TOP/target/release"
      install -Dm555 "$target/openhuman-core" "$out/bin/openhuman-core"
      install -Dm555 "$target/OpenHuman" "$out/bin/OpenHuman"

      # Tauri finds Linux resources at ../lib/<productName>. The native
      # mascot/notch windows also load index.html directly from this directory.
      mkdir -p "$out/lib/OpenHuman"
      cp -R app/dist/. "$out/lib/OpenHuman/"
      mkdir -p "$out/lib/OpenHuman/_up_/_up_/crates/openhuman-core/src/agent"
      cp -R crates/openhuman-core/src/agent/prompts \
        "$out/lib/OpenHuman/_up_/_up_/crates/openhuman-core/src/agent/"

      for size in 32 64 128; do
        install -Dm444 "crates/openhuman-app/icons/''${size}x''${size}.png" \
          "$out/share/icons/hicolor/''${size}x''${size}/apps/OpenHuman.png"
      done
      install -Dm444 crates/openhuman-app/icons/128x128@2x.png \
        "$out/share/icons/hicolor/256x256/apps/OpenHuman.png"
      install -Dm444 crates/openhuman-app/icons/icon.png \
        "$out/share/icons/hicolor/512x512/apps/OpenHuman.png"

      runHook postInstall
    '';

    preFixup = ''
      gappsWrapperArgs+=(--prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ libayatana-appindicator ]}")
    '';

    desktopItems = [
      (makeDesktopItem {
        name = "OpenHuman";
        desktopName = "OpenHuman";
        exec = "OpenHuman %U";
        icon = "OpenHuman";
        categories = [ "Utility" ];
        mimeTypes = [ "x-scheme-handler/openhuman" ];
      })
    ];

    doInstallCheck = true;
    nativeInstallCheckInputs = [ versionCheckHomeHook ];
    installCheckPhase = ''
      runHook preInstallCheck

      # The CLI exposes its version through JSON-RPC, not a --version flag.
      out_version="$($out/bin/openhuman-core call --method core.version)"
      echo "$out_version" | grep -F '"${finalAttrs.version}"' > /dev/null
      app_version="$($out/bin/OpenHuman core call --method core.version)"
      echo "$app_version" | grep -F '"${finalAttrs.version}"' > /dev/null

      test -x "$out/bin/OpenHuman"
      test -f "$out/lib/OpenHuman/index.html"
      test -f "$out/share/applications/OpenHuman.desktop"
      test -f "$out/share/icons/hicolor/128x128/apps/OpenHuman.png"

      runHook postInstallCheck
    '';

    passthru = {
      category = "AI Assistants";
      inherit cargoDepsCli cargoDepsApp;
    };

    meta = {
      description = "Personal AI super intelligence: local-first memory, agent fleet orchestration, and deep research";
      homepage = "https://github.com/tinyhumansai/openhuman";
      # Upstream publishes releases behind the tags; releases/tag/v${version}
      # 404s until they catch up, so point at the releases page.
      changelog = "https://github.com/tinyhumansai/openhuman/releases";
      license = lib.licenses.gpl3Only;
      sourceProvenance = [ lib.sourceTypes.fromSource ];
      maintainers = with flake.lib.maintainers; [ smdex ];
      mainProgram = "openhuman-core";
      platforms = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };
  });
in
stdenv.mkDerivation {
  inherit (compiled)
    pname
    version
    meta
    buildInputs
    ;
  dontUnpack = true;
  dontBuild = true;
  strictDeps = true;
  nativeBuildInputs = [ wrapGAppsHook3 ];

  # Keep compilation separate from runtime wrapping. The real executables must
  # remain siblings: Tauri resolves resources and its MCP CLI from current_exe.
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    install -m555 ${compiled}/bin/.OpenHuman-wrapped "$out/bin/OpenHuman"
    install -m555 ${compiled}/bin/.openhuman-core-wrapped "$out/bin/openhuman-core"
    ln -s ${compiled}/lib "$out/lib"
    ln -s ${compiled}/share "$out/share"
    runHook postInstall
  '';
  preFixup = compiled.preFixup + ''
    # OpenHuman's default Node runtime accepts system Node 22. Its downloaded
    # upstream binaries require a conventional ELF interpreter unavailable on NixOS.
    gappsWrapperArgs+=(--prefix PATH : "${lib.makeBinPath [ nodejs_22 ]}")
  '';
  inherit (compiled) doInstallCheck installCheckPhase;
  nativeInstallCheckInputs = [ versionCheckHomeHook ];
  passthru = compiled.passthru // {
    inherit pnpmDeps;
    unwrapped = compiled;
  };
}
