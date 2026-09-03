{
  lib,
  flake,
  stdenv,
  runCommand,
  rustPlatform,
  cargo,
  rustc,
  fetchurl,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs_24,
  cmake,
  ninja,
  patchelf,
  pkg-config,
  versionCheckHomeHook,
  bzip2,
  freetype,
  gdk-pixbuf,
  harfbuzz,
  libepoxy,
  # Build-time (link) native dependencies of the Rust crates.
  alsa-lib,
  fontconfig,
  libxkbcommon,
  xdotool,
  libx11,
  libxcomposite,
  libxcursor,
  libxdamage,
  libxext,
  libxfixes,
  libxi,
  libxinerama,
  libxrandr,
  libxrender,
  libxtst,
  libxcb,
  llvmPackages,
  libclang,
  # Runtime dependencies of the prebuilt CEF payload (rpath-patched at
  # install time; see runtimeLibPath).
  at-spi2-atk,
  at-spi2-core,
  atk,
  cairo,
  cups,
  dbus,
  expat,
  glib,
  gtk3,
  libgbm,
  nspr,
  nss,
  pango,
  systemd,
  wayland,
  webkitgtk_4_1,
  libsoup_3,
}:

let
  data = builtins.fromJSON (builtins.readFile ./hashes.json);

  # Upstream dropped the CEF desktop engine after 0.63.12 (the app lockfile
  # no longer carries cef-dll-sys and the tauri-cef vendor submodule is
  # gone). The updater retires the "cef" section from hashes.json once the
  # pinned tag crosses that boundary; while it is present — as for the
  # currently pinned 0.63.12 — the CEF path below stays in force unchanged
  # and the stock tauri webkitgtk shell is built without it.
  hasCef = data ? cef;

  pnpm = pnpm_10;

  # ── Upstream source ─────────────────────────────────────────────────────
  # The tag's tree records the repo's git submodules as gitlinks;
  # fetchFromGitHub archives do not carry them, so each is fetched
  # separately at the exact recorded rev and overlaid onto the main tree in
  # fullSrc. The updater derives the set from the tag's gitlink tree plus
  # `.gitmodules` and records path -> {owner, repo, rev, hash} in
  # hashes.json, so upstream submodule churn needs no edits here; nested
  # submodules below the vendor/* crates are either docs-only wikis or
  # unpopulated at these pins (verified), so one level is enough.
  src = fetchFromGitHub {
    owner = "tinyhumansai";
    repo = "openhuman";
    tag = "v${data.version}";
    hash = data.hash;
  };

  submoduleSource =
    path: meta:
    fetchFromGitHub {
      owner = meta.owner;
      repo = meta.repo;
      name = "openhuman-submodule-${builtins.baseNameOf path}";
      inherit (meta) rev hash;
    };

  # Main tree + submodules at their pinned revs, exactly what
  # `git clone --recursive` at the tag would produce (modulo .git). A plain
  # store-path assembly — the usual coreutils suffice, no toolchain needed.
  fullSrc = runCommand "openhuman-${data.version}-src" { } ''
    cp -TR ${src} $out
    chmod -R u+w $out
    ${lib.concatStrings (
      lib.mapAttrsToList (path: meta: ''
        mkdir -p $out/$(dirname ${path})
        cp -TR ${submoduleSource path meta} $out/${path}
      '') data.submodules
    )}
  '';

  # ── JavaScript dependencies (pnpm workspace at the repo root) ───────────
  pnpmDeps = fetchPnpmDeps {
    pname = "openhuman";
    inherit src;
    inherit pnpm;
    fetcherVersion = 4;
    hash = data.pnpmDeps;
  };

  # ── Rust dependencies ───────────────────────────────────────────────────
  # Upstream has two independent cargo worlds with separate lockfiles:
  # the repo root (openhuman-core CLI) and app/src-tauri (the Tauri/CEF
  # desktop shell, which links the core crate in via `path = "../.."`).
  # Each world gets its own vendored dependency set.
  cargoDepsCli = rustPlatform.fetchCargoVendor {
    name = "openhuman-${data.version}-cli-deps";
    src = fullSrc;
    hash = data.cargoCliDeps;
  };

  cargoDepsApp = rustPlatform.fetchCargoVendor {
    name = "openhuman-${data.version}-app-deps";
    src = fullSrc;
    cargoRoot = "app/src-tauri";
    hash = data.cargoAppDeps;
  };

  # ── CEF (Chromium Embedded Framework) binary distribution ───────────────
  # The desktop app embeds tauri-runtime-cef instead of webkitgtk; cef-dll-sys
  # builds libcef_dll_wrapper against this pinned binary distribution and
  # copies the Chromium runtime next to the built binary. We pin the tarball
  # hash from the Spotify CDN and repackage it into the exact layout the
  # cef-dll-sys build script expects under CEF_PATH:
  #   $out/<cef-version>/cef_linux_<arch>/{libcef.so,…,archive.json}
  # (mirroring download-cef's own extract logic, so the build never downloads).
  cefPlatform = if stdenv.hostPlatform.isAarch64 then "linuxarm64" else "linux64";
  cefOsArch = "cef_linux_${stdenv.hostPlatform.parsed.cpu.name}";

  # Parameterized so the aarch64 dist can be built (and hash-pinned) from any
  # host — the transformation is pure data, no target toolchain involved.
  cefDistFor =
    {
      platform,
      osArch,
    }:
    let
      archive = data.cef.archives.${platform};
    in
    stdenv.mkDerivation {
      name = "cef-${data.cef.cefVersion}-${platform}-dist";
      src = fetchurl {
        url = "https://cef-builds.spotifycdn.com/${archive.name}";
        hash = archive.tarballHash;
      };
      outputHash = archive.distHash;
      outputHashAlgo = "sha256";
      outputHashMode = "recursive";

      # llvm-strip (not binutils) so foreign-architecture dists can be
      # trimmed from any build host.
      nativeBuildInputs = [ llvmPackages.llvm ];

      buildPhase = ''
        runHook preBuild

        versioned="$out/${data.cef.cefVersion}"
        mkdir -p "$versioned"
        tar -xjf "$src" -C "$versioned"
        extracted="$(echo "$versioned"/cef_binary_*_minimal)"
        cefdir="$versioned/${osArch}"

        # Replicate download-cef's extraction: Release/ becomes the cef dir,
        # Resources/* are merged in (non-macos), plus the wrapper build inputs.
        mv "$extracted/Release" "$cefdir"
        for entry in "$extracted"/Resources/*; do
          mv "$entry" "$cefdir/"
        done
        mv "$extracted/CMakeLists.txt" "$cefdir/"
        for extra in cmake include libcef_dll CREDITS.html; do
          if [ -e "$extracted/$extra" ]; then mv "$extracted/$extra" "$cefdir/"; fi
        done
        rm -rf "$extracted"

        # libcef.so ships ~1.2 GB with debug sections; strip like the upstream
        # deb bundler does. Stripping keeps the dynamic symbol table intact.
        for elf in libcef.so libEGL.so libGLESv2.so libvk_swiftshader.so libvulkan.so.1 chrome-sandbox; do
          if [ -f "$cefdir/$elf" ]; then llvm-strip --strip-debug "$cefdir/$elf"; fi
        done

        # Marker consumed by cef-dll-sys (check_archive_json) proving this tree
        # matches the expected CEF version.
        printf '{\n  "sha1": "%s",\n  "type": "minimal",\n  "name": "%s"\n}\n' \
          '${archive.sha1}' '${archive.name}' > "$cefdir/archive.json"

        runHook postBuild
      '';

      dontConfigure = true;
      dontInstall = true;
      dontFixup = true;
    };
  cefDist = cefDistFor {
    platform = cefPlatform;
    osArch = cefOsArch;
  };

  # RPATH for the shipped ELFs: the binary's own NEEDED set (≈ buildInputs)
  # plus libcef's, so both resolve entirely from the Nix store.
  runtimeLibPath = lib.makeLibraryPath ([
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    freetype
    gdk-pixbuf
    harfbuzz
    libepoxy
    glib
    gtk3
    libgbm
    libxkbcommon
    nspr
    nss
    pango
    systemd
    wayland
    bzip2
    alsa-lib
    fontconfig
    xdotool
    (lib.getLib stdenv.cc.cc)
    libx11
    libxcomposite
    libxcursor
    libxdamage
    libxext
    libxfixes
    libxi
    libxinerama
    libxrandr
    libxrender
    libxtst
    libxcb
  ]);

in
stdenv.mkDerivation (finalAttrs: {
  pname = "openhuman";
  version = data.version;

  src = fullSrc;

  strictDeps = true;

  # cmake/ninja are driven by the Rust `cmake` crate inside the cargo builds,
  # not by stdenv's configure phase.
  dontUseCmakeConfigure = true;

  nativeBuildInputs = [
    cargo
    rustc
    cmake
    ninja
    patchelf
    pkg-config
    nodejs_24
    pnpm
    pnpmConfigHook
    versionCheckHomeHook
    libclang
  ];

  buildInputs = [
    # Native libs the Rust crates link (alsa/cpal, fontconfig/resvg,
    # xkbcommon+Xtst/enigo, xdo, gtk3/tauri) plus everything libcef.so
    # itself resolves against — the final executable link has to provide
    # the whole set for the prebuilt Chromium payload.
    alsa-lib
    fontconfig
    glib
    gtk3
    libxkbcommon
    xdotool
    libx11
    libxi
    libxrandr
    libxtst
    at-spi2-atk
    at-spi2-core
    atk
    cairo
    cups
    dbus
    expat
    freetype
    gdk-pixbuf
    harfbuzz
    libepoxy
    libgbm
    nspr
    nss
    pango
    systemd
    wayland
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxcb
  ]
  ++ lib.optionals (!hasCef) [
    # Stock tauri webview once the CEF engine is dropped upstream.
    webkitgtk_4_1
    libsoup_3
  ];

  inherit pnpmDeps;

  # For the bindgen-based crates (whisper-rs-sys, …).
  LIBCLANG_PATH = "${lib.getLib libclang}/lib";

  # The frontend build (tsc + vite) is driven by the workspace root lockfile;
  # the `tsc` type-check gate is skipped — it gates nothing at runtime.
  buildPhase = ''
    runHook preBuild

    # Two cargo worlds, two isolated CARGO_HOMEs, each wired to its own
    # vendored dependency set. The vendor outputs are copied writable first
    # (tauri-plugin build scripts generate permission schemas inside their
    # crate sources, so the read-only store paths will not do). Builds run
    # from a neutral cwd so only the CARGO_HOME config — and no source-tree
    # .cargo config — is in play.
    makeCargoHome() {
      local home="$1" deps="$2" writable="$3"
      cp -R "$deps" "$writable"
      chmod -R u+w "$writable"
      mkdir -p "$home"
      # cargo reads $CARGO_HOME/config.toml (flat), not a nested .cargo/ dir.
      substitute "$writable/.cargo/config.toml" "$home/config.toml" \
        --subst-var-by vendor "$writable"
    }
    makeCargoHome "$NIX_BUILD_TOP/cargo-home-cli" "${cargoDepsCli}" "$NIX_BUILD_TOP/vendor-cli"
    makeCargoHome "$NIX_BUILD_TOP/cargo-home-app" "${cargoDepsApp}" "$NIX_BUILD_TOP/vendor-app"
    export CARGO_BUILD_JOBS=$NIX_BUILD_CORES
    export CARGO_NET_OFFLINE=true
    # One shared target dir for both cargo worlds (they share most crates;
    # cargo keeps separate fingerprints per workspace root).
    export CARGO_TARGET_DIR="$NIX_BUILD_TOP/target"

    # 1) Frontend: vite bundle into app/dist (consumed by tauri-build's
    #    custom-protocol codegen in step 3).
    pnpm --filter openhuman-app exec vite build

    # 2) openhuman-core CLI (root cargo world).
    export CARGO_HOME="$NIX_BUILD_TOP/cargo-home-cli"
    cargo build \
      --release --locked --offline \
      --manifest-path "$PWD/Cargo.toml" \
      --bin openhuman-core

    # 3) Desktop shell (app/src-tauri cargo world). While CEF is pinned,
    #    custom-protocol embeds app/dist; cef-dll-sys reads CEF_PATH (never
    #    downloads) and copies the Chromium runtime next to the produced
    #    binary, and rpath-link lets the final executable link resolve the
    #    prebuilt libcef.so's full NEEDED closure from the store. Once CEF
    #    is dropped it is the stock tauri webkitgtk shell.
    export CARGO_HOME="$NIX_BUILD_TOP/cargo-home-app"
    shellFeatures=""
    ${lib.optionalString hasCef ''
      export CEF_PATH="${cefDist}"
      export RUSTFLAGS="-C link-arg=-Wl,--rpath-link=${runtimeLibPath}"
      shellFeatures="--features custom-protocol"
    ''}
    cargo build \
      --release --locked --offline \
      --manifest-path "$PWD/app/src-tauri/Cargo.toml" \
      --bin OpenHuman \
      $shellFeatures

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    target="$NIX_BUILD_TOP/target/release"

    # ── CLI ──
    install -Dm555 "$target/openhuman-core" "$out/bin/openhuman-core"

    # ── Desktop shell (+ CEF runtime while the engine is pinned) ──
    # The CEF runtime payload is installed from the pinned dist itself
    # (canonical, deterministic — independent of what cef-dll-sys copies
    # into the target dir); we mirror the upstream .deb layout: everything
    # beside the executable, en-US locale only.
    appdir="$out/lib/OpenHuman"
    mkdir -p "$appdir"
    install -m755 "$target/OpenHuman" "$appdir/OpenHuman"
    ${lib.optionalString hasCef ''
      cefdir="${cefDist}/${data.cef.cefVersion}/${cefOsArch}"
      mkdir -p "$appdir/locales"
      for f in \
        libcef.so icudtl.dat v8_context_snapshot.bin snapshot_blob.bin \
        chrome_100_percent.pak chrome_200_percent.pak resources.pak \
        libEGL.so libGLESv2.so libvk_swiftshader.so vk_swiftshader_icd.json \
        libvulkan.so.1
      do
        if [ -f "$cefdir/$f" ]; then
          install -m755 "$cefdir/$f" "$appdir/$f"
        fi
      done
      install -Dm444 "$cefdir/locales/en-US.pak" "$appdir/locales/en-US.pak"

      # Point the prebuilt CEF payload at the Nix store for its own NEEDED
      # libs; drop the cefDist store path the linker baked into the shell's
      # rpath so the closure does not carry the runtime twice.
      for elf in "$appdir"/libcef.so "$appdir"/libEGL.so "$appdir"/libGLESv2.so \
        "$appdir"/libvk_swiftshader.so "$appdir"/libvulkan.so.1
      do
        [ -f "$elf" ] && patchelf --set-rpath "$appdir:${runtimeLibPath}" "$elf"
      done
      # Replace the linker-baked rpath ($ORIGIN + the cefDist store path) with
      # the install dir plus the Nix store library set, so the closure does not
      # carry the whole CEF runtime and every direct/indirect NEEDED resolves.
      patchelf --set-rpath "$appdir:${runtimeLibPath}" "$appdir/OpenHuman"
    ''}
    ln -s ../lib/OpenHuman/OpenHuman "$out/bin/OpenHuman"

    # ── Desktop entry + icons (from the tauri bundle metadata) ──
    install -Dm444 "$PWD/app/src-tauri/icons/32x32.png" \
      "$out/share/icons/hicolor/32x32/apps/OpenHuman.png"
    install -Dm444 "$PWD/app/src-tauri/icons/64x64.png" \
      "$out/share/icons/hicolor/64x64/apps/OpenHuman.png"
    install -Dm444 "$PWD/app/src-tauri/icons/128x128.png" \
      "$out/share/icons/hicolor/128x128/apps/OpenHuman.png"
    install -Dm444 "$PWD/app/src-tauri/icons/128x128@2x.png" \
      "$out/share/icons/hicolor/256x256/apps/OpenHuman.png"
    install -Dm444 "$PWD/app/src-tauri/icons/icon.png" \
      "$out/share/icons/hicolor/512x512/apps/OpenHuman.png"
    install -Dm644 -T "$PWD/app/src-tauri/main.desktop" \
      "$out/share/applications/OpenHuman.desktop"
    substituteInPlace "$out/share/applications/OpenHuman.desktop" \
      --replace-fail '{{categories}}' "Utility;" \
      --replace-fail '{{exec}}' "OpenHuman" \
      --replace-fail '{{icon}}' "OpenHuman" \
      --replace-fail '{{name}}' "OpenHuman"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    # The CLI has no --version flag; `call --method core.version` is the
    # canonical version RPC.
    out_version="$($out/bin/openhuman-core call --method core.version)"
    echo "$out_version" | grep -F '"${finalAttrs.version}"' > /dev/null

    # The desktop shell multiplexes the core CLI behind its `core`
    # subcommand — doubles as a headless smoke test that the ELF and its
    # libcef.so resolve from the install layout.
    app_version="$($out/bin/OpenHuman core call --method core.version)"
    echo "$app_version" | grep -F '"${finalAttrs.version}"' > /dev/null

    test -x "$out/lib/OpenHuman/OpenHuman"
    ${lib.optionalString hasCef ''
      test -f "$out/lib/OpenHuman/libcef.so"
      test -f "$out/lib/OpenHuman/icudtl.dat"
    ''}
    test -f "$out/share/applications/OpenHuman.desktop"
    test -f "$out/share/icons/hicolor/128x128/apps/OpenHuman.png"

    runHook postInstallCheck
  '';

  passthru = {
    category = "AI Assistants";
    inherit cargoDepsCli cargoDepsApp;
  }
  // lib.optionalAttrs hasCef {
    cefDist = cefDistFor {
      platform = cefPlatform;
      osArch = cefOsArch;
    };
    cefDistArm64 = cefDistFor {
      platform = "linuxarm64";
      osArch = "cef_linux_aarch64";
    };
  };

  meta = {
    description = "Personal AI super intelligence: local-first memory, agent fleet orchestration, and deep research";
    homepage = "https://github.com/tinyhumansai/openhuman";
    # Upstream publishes releases behind the tags; releases/tag/v${version}
    # 404s until they catch up, so point at the releases page.
    changelog = "https://github.com/tinyhumansai/openhuman/releases";
    license = lib.licenses.gpl3Only;
    sourceProvenance =
      with lib.sourceTypes;
      [ fromSource ]
      ++ lib.optionals hasCef [
        binaryNativeCode # CEF (Chromium) runtime from the pinned binary dist
      ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "openhuman-core";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
