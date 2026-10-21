{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  formatelf,
  ripgrep,
  fd,
  bun,
  bun2nixLib,
  versionCheckHook,
  versionCheckHomeHook,
  mkUpdater,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;

  # JS `process.platform`-`process.arch` triplet the runtime resolvers use
  # (scripts/build.ts, src/core/utils/hydrate-runtime.ts).
  triplet =
    {
      x86_64-linux = "linux-x64";
      aarch64-linux = "linux-arm64";
      aarch64-darwin = "darwin-arm64";
      x86_64-darwin = "darwin-x64";
    }
    .${stdenv.hostPlatform.system};

  nativeLib = if stdenv.hostPlatform.isDarwin then "libopentui.dylib" else "libopentui.so";

  # Search backbones spawned by the soul_grep/soul tools. Upstream bundles
  # these next to the binary (scripts/bundle.sh); on nix a PATH prefix is the
  # equivalent — getVendoredPath() misses ~/.soulforge/bin and falls back to
  # PATH lookup (src/core/tools/util.ts).
  runtimePath = lib.makeBinPath [
    ripgrep
    fd
  ];
in
stdenv.mkDerivation {
  pname = "empryo";
  inherit version;

  src = fetchFromGitHub {
    owner = "proxysoul";
    repo = "Empryo";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    bun
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib # libstdc++/libgcc_s for the OpenTUI native libs
  ];

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
  };

  # Upstream imports transitive deps from source (e.g. `import
  # "@opentui/core"` in src/, a peer of ghostty-opentui and a direct dep only
  # of @opentui/react). The hook's default `--linker=isolated` leaves those
  # unlinked at node_modules/ root and the bundler cannot resolve them —
  # match upstream's hoisted dev layout instead.
  bunInstallFlags = [ "--linker=hoisted" ];

  # Upstream build (scripts/build.ts, two-phase Bun.build with the React
  # Compiler plugin) — nothing for the hook's default `bun build` to do.
  dontUseBunBuild = true;
  # The hook's pre-build `bun install` still runs (it creates node_modules);
  # skip its lifecycle re-install and postinstall (hydrates ~/.soulforge —
  # a build-time HOME, pointless in the sandbox).
  dontRunLifecycleScripts = true;

  # bun's offline resolver refuses semver ranges (^/~) when only one version
  # is present in the store cache — collapse to exact pins, matching the
  # versions already recorded in bun.lock (same treatment as packages/hunk).
  postPatch = ''
    sed -i 's/: "\^/: "/g; s/: "~/: "/g' package.json bun.lock
  '';

  buildPhase = ''
    runHook preBuild

    export SOULFORGE_SKIP_SMOKE=1 # installCheck verifies --version instead
    bun scripts/build.ts --compile

    # ── Runtime deps that cannot be embedded in a compiled binary ──
    # Mirrors scripts/bundle.sh: hydrate-runtime.ts copies $out/deps into
    # ~/.soulforge on first boot, so the store tree must match its layout.
    depsRoot=deps
    mkdir -p "$depsRoot"/{workers,wasm,opentui-assets,native/${triplet}}

    # Workers are loaded as separate files at runtime.
    for w in intelligence io; do
      bun build "src/core/workers/$w.worker.ts" \
        --outdir "$depsRoot/workers" \
        --entry-naming "[name].[ext]" \
        --target=bun \
        --external "*.node" --external "*.wasm" --external "*.scm"
    done

    # tree-sitter runtime + grammar WASMs.
    cp node_modules/web-tree-sitter/tree-sitter.wasm "$depsRoot/wasm/" \
      || cp node_modules/web-tree-sitter/web-tree-sitter.wasm "$depsRoot/wasm/tree-sitter.wasm"
    cp node_modules/tree-sitter-wasms/out/*.wasm "$depsRoot/wasm/"

    # OpenTUI syntax assets + pre-bundled parser worker, patched to resolve
    # tree-sitter.wasm from ~/.soulforge/wasm (sed patterns from bundle.sh;
    # kept non-fatal because the bundled identifier names can drift).
    cp -r node_modules/@opentui/core/assets/. "$depsRoot/opentui-assets/"
    bun build node_modules/@opentui/core/parser.worker.js \
      --outdir "$depsRoot/opentui-assets" \
      --target=bun \
      --asset-naming "[name].[ext]"
    sed -i \
      -e 's|module2.exports = "./tree-sitter.wasm"|module2.exports = (__require("os").homedir() + "/.soulforge/wasm/tree-sitter.wasm")|' \
      -e 's|var fs = require("fs")|var fs = __require("fs")|g' \
      -e 's|var nodePath = require("path")|var nodePath = __require("path")|g' \
      -e 's|require("url")|__require("url")|g' \
      "$depsRoot/opentui-assets/parser.worker.js" || true

    # Native addons: the @opentui/core-<triplet> lib + ghostty-opentui.node
    # are dlopen'd at runtime from ~/.soulforge/native/<triplet>/.
    cp "node_modules/@opentui/core-${triplet}/${nativeLib}" "$depsRoot/native/${triplet}/"
    cp "node_modules/ghostty-opentui/dist/${triplet}/ghostty-opentui.node" "$depsRoot/native/${triplet}/"

    cp src/core/editor/init.lua "$depsRoot/init.lua"

    runHook postBuild
  '';

  # `bun build --compile` embeds the JS bundle at the tail of the binary;
  # stripping corrupts it.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    install -Dm755 soulforge $out/libexec/soulforge
    mkdir -p $out/bin
    makeWrapper $out/libexec/soulforge $out/bin/soulforge \
      --prefix PATH : "${runtimePath}"
    ln -s soulforge $out/bin/sf

    # hydrate-runtime.ts probes dirname(execPath)/../deps → $out/deps.
    cp -r deps $out/deps

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "bun-github";
    purl = "pkg:github/proxysoul/Empryo";
  };

  meta = {
    description = "Graph-powered code intelligence — multi-agent coding with codebase-aware AI (formerly SoulForge)";
    homepage = "https://empryo.com";
    changelog = "https://github.com/proxysoul/Empryo/releases/tag/v${version}";
    # Business Source License 1.1 (see LICENSE). Change Date 2030-03-15, then
    # Apache-2.0. The Additional Use Grant permits personal/internal use;
    # commercial offering to third parties requires a commercial license.
    # Inline because nixpkgs has no `licenses.busl`; `free = true` follows
    # this repo's convention for source-available licenses (lib/default.nix
    # does the same for fsl11Mit) so the package evaluates without
    # allowUnfree — the license terms still apply.
    license = {
      spdxId = "BUSL-1.1";
      fullName = "Business Source License 1.1";
      url = "https://mariadb.com/bsl11/";
      free = true;
      deprecated = false;
    };
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode # prebuilt @opentui/<triplet> + ghostty-opentui.node from npm
    ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "soulforge";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
  };
}
