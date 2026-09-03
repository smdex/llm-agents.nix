{
  lib,
  flake,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  applyPatches,
  fetchPnpmDeps,
  goose-cli,
  cargo-tauri,
  jq,
  moreutils,
  nodejs,
  git,
  pnpm_10,
  pnpmConfigHook,
  pkg-config,
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
  sourceRevision = "612cd89d515f16c84f70b4c74247e270277fe7ba";
  version = "0.1.0";

  gooseSrc = fetchFromGitHub {
    owner = "aaif-goose";
    repo = "goose";
    rev = sourceRevision;
    hash = "sha256-YwNpO4a32eon7gWq1FKm6NOw0ZaVQMcJ5byHBFr+5/w=";
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

  desktop = rustPlatform.buildRustPackage (_finalAttrs: {
    pname = "goose2";
    inherit version;
    src = gooseSrc;

    cargoRoot = "ui/goose2/src-tauri";
    cargoHash = "sha256-PDa/h/l2Ck0PZqIEGhK92R27eqgegRyoqWsJ/UyfQJY=";

    pnpmDeps = fetchPnpmDeps {
      pname = "goose2-ui";
      inherit version;
      src = gooseSrc;
      sourceRoot = "${gooseSrc.name}/ui";
      inherit pnpm;
      fetcherVersion = 3;
      hash = "sha256-fWt0R1x7jiAJaUJUty5BsJDb3jXJl7I1Hh0LHByTN60=";
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
      # `goose-tauri` is an implementation binary. Keep it private: launching
      # it directly bypasses GOOSE_BIN and makes Tauri resolve its fallback
      # sidecar instead of the source-built Goose 2 CLI.
      install -Dm755 target/${stdenv.hostPlatform.rust.rustcTarget}/release/goose-tauri \
        $out/libexec/goose2/goose-tauri
      makeWrapper $out/libexec/goose2/goose-tauri $out/bin/goose2 \
        --set GOOSE_BIN ${lib.getExe goose-cli} \
        --prefix PATH : ${
          lib.makeBinPath [
            goose-cli
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
      changelog = "https://github.com/aaif-goose/goose/releases";
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
      test ! -e $out/bin/goose-tauri
      test -x $out/libexec/goose2/goose-tauri
      test -f "$out/bin/goose2"
      grep -F -- "${lib.getExe goose-cli}" "$out/bin/.goose2-wrapped"
      grep -F -- "${bashInteractive}/bin/bash" "$out/bin/.goose2-wrapped"
      grep -F -- "${goose-cli}/bin" "$out/bin/.goose2-wrapped"
      runHook postInstallCheck
    '';
  });
in
desktop
