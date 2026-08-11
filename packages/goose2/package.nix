{
  lib,
  flake,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  applyPatches,
  callPackage,
  fetchPnpmDeps,
  cargo-tauri,
  jq,
  moreutils,
  nodejs,
  git,
  pnpm_10,
  pnpmConfigHook,
  pkg-config,
  cmake,
  wrapGAppsHook3,
  makeWrapper,
  bashInteractive,
  zsh,
  coreutils,
  findutils,
  gnugrep,
  which,
  gh,
  git-lfs,
  openssl,
  libxcb,
  dbus,
  gtk3,
  glib,
  glib-networking,
  libsoup_3,
  webkitgtk_4_1,
  cairo,
  pango,
  atk,
  gdk-pixbuf,
  librsvg,
}:

let
  pnpm = pnpm_10;
  fetchLibrustyV8 = (callPackage ../goose-cli/fetchers.nix { }).fetchLibrustyV8;
  librusty_v8 = callPackage ../goose-cli/librusty_v8.nix { inherit fetchLibrustyV8; };
  upstreamTag = "v2.0.0-rc-04-27-0";
  version = "0.1.0";

  gooseSrc = fetchFromGitHub {
    owner = "aaif-goose";
    repo = "goose";
    tag = upstreamTag;
    hash = "sha256-BKSUjvHa9bQxE3ZeMY4ayvrIWM5/Il9E8qupu+ZQMII=";
  };

  builderbotPatched = applyPatches {
    src = fetchFromGitHub {
      owner = "block";
      repo = "builderbot";
      rev = "8e1c3ec145edc0df5f04b4427cfd758378036862";
      hash = "sha256-NAtFvQ1QlSYgmnDSJqj0OrORCA0wmWuYaKnZJXmLsSA=";
    };
    patches = [ ./doctor-nixos.patch ];
  };

  # Goose 2 expects the CLI from the same release line. This is deliberately a
  # separate source derivation: the legacy goose-cli package is v1.45.0 and
  # must not be silently embedded in a v2 preview application.
  goose2Cli = rustPlatform.buildRustPackage {
    pname = "goose2-cli";
    inherit version;
    src = gooseSrc;
    cargoHash = "sha256-X1DdDiWCwD5ykkVW5A4eiv0VIswwMPdpTqMmzt1x6Cc=";
    cargoBuildFlags = [
      "--package"
      "goose-cli"
    ];
    nativeBuildInputs = [
      pkg-config
      cmake
      rustPlatform.bindgenHook
    ];
    dontUseCmakeConfigure = true;
    buildInputs = [
      openssl
      libxcb
      dbus
    ];
    env.RUSTY_V8_ARCHIVE = librusty_v8;
    doCheck = false;
    installPhase = ''
      install -Dm755 target/${stdenv.hostPlatform.rust.rustcTarget}/release/goose $out/bin/goose
    '';
  };

  desktop = rustPlatform.buildRustPackage (_finalAttrs: {
    pname = "goose2";
    inherit version;
    src = gooseSrc;

    cargoRoot = "ui/goose2/src-tauri";
    cargoHash = "sha256-6tZ/ue7cDeTMSm8mF9DJtL9uP8R/08Yv1JIaZKnRZFI=";

    pnpmDeps = fetchPnpmDeps {
      pname = "goose2-ui";
      inherit version;
      src = gooseSrc;
      sourceRoot = "${gooseSrc.name}/ui";
      inherit pnpm;
      fetcherVersion = 3;
      hash = "sha256-DdLhGEKPSKJEF9LyOqBY4BR/JB/o6t9VfQGXWQmMDEI=";
    };
    pnpmRoot = "ui";

    postPatch = ''
      # Use the patched, vendored Doctor crate without changing the upstream
      # Cargo.lock entry or maintaining a fork.
      mkdir -p ui/goose2/src-tauri/vendor-patches
      ln -s ${builderbotPatched} ui/goose2/src-tauri/vendor-patches/builderbot
      cat >> ui/goose2/src-tauri/Cargo.toml <<'EOF'

      [patch."https://github.com/block/builderbot"]
      doctor = { path = "vendor-patches/builderbot/crates/doctor" }
      EOF

      # The sidecar is supplied as a store symlink through GOOSE_BIN. This
      # avoids copying a second Goose executable into the Tauri bundle.
      jq '.bundle.externalBin = []' ui/goose2/src-tauri/tauri.conf.json | sponge ui/goose2/src-tauri/tauri.conf.json
    '';

    nativeBuildInputs = [
      cargo-tauri
      jq
      moreutils
      nodejs
      git
      pnpm
      pnpmConfigHook
      pkg-config
      wrapGAppsHook3
      makeWrapper
    ];

    buildInputs = [
      cairo
      glib
      glib-networking
      gtk3
      libsoup_3
      openssl
      pango
      atk
      gdk-pixbuf
      librsvg
      webkitgtk_4_1
    ];

    # Tauri's beforeBuildCommand runs this too, but doing it explicitly makes
    # the workspace dependency and generated SDK deterministic under pnpm's
    # offline hook.
    preBuild = ''
      cd ui
      pnpm --filter @aaif/goose-sdk build
      pnpm --filter goose2 build
      cd ../..
    '';

    dontCargoBuild = true;
    dontCargoInstall = true;

    buildPhase = ''
      runHook preBuild
      tauriDir=$(dirname "$(find "$PWD" -path '*/ui/goose2/src-tauri/Cargo.toml' -print -quit)")
      cd "$tauriDir"
      cargo tauri build --bundles deb --target ${stdenv.hostPlatform.rust.rustcTarget} -- --offline
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 target/${stdenv.hostPlatform.rust.rustcTarget}/release/goose-tauri $out/bin/goose-tauri
      makeWrapper $out/bin/goose-tauri $out/bin/goose2 \
        --set GOOSE_BIN ${goose2Cli}/bin/goose \
        --prefix PATH : ${
          lib.makeBinPath [
            goose2Cli
            git
            gh
            git-lfs
            bashInteractive
            zsh
            coreutils
            findutils
            gnugrep
            which
          ]
        } \
        --set SHELL ${bashInteractive}/bin/bash
      runHook postInstall
    '';

    passthru.category = "AI Coding Agents";

    meta = {
      description = "Goose 2 Tauri desktop app built from source";
      homepage = "https://github.com/aaif-goose/goose";
      changelog = "https://github.com/aaif-goose/goose/releases/tag/${upstreamTag}";
      license = lib.licenses.asl20;
      sourceProvenance = with lib.sourceTypes; [ fromSource ];
      maintainers = with flake.lib.maintainers; [ smdex ];
      mainProgram = "goose2";
      platforms = [ "x86_64-linux" ];
    };

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test -x $out/bin/goose2
      test -x $out/bin/goose-tauri
      wrapper=$out/bin/goose2
      test -f "$wrapper"
      grep -F -- "${goose2Cli}/bin/goose" "$out/bin/.goose2-wrapped"
      grep -F -- "${bashInteractive}/bin/bash" "$out/bin/.goose2-wrapped"
      grep -F -- "${goose2Cli}/bin" "$out/bin/.goose2-wrapped"
      runHook postInstallCheck
    '';
  });
in
desktop
