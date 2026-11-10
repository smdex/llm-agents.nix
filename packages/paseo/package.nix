{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  buildNpmPackage,
  nodejs_22,
  python3,
  makeWrapper,
  formatelf,
  versionCheckHook,
  versionCheckHomeHook,
  # node-pty needs libuv headers on Linux
  libuv,
  # Exposed so downstream flakes that follow a different nixpkgs revision
  # (where `fetchNpmDeps` may produce a different hash for the same lockfile)
  # can override via `.override { npmDepsHash = "sha256-..."; }` without
  # `overrideAttrs` gymnastics.
  npmDepsHash ?
    {
      x86_64-linux = "sha256-0KME5hEqTcSpyl75yqzODdTE0ZyZjZBiTLC35Q3zg4A=";
      aarch64-linux = "sha256-AgIKnoKgWctPEOKm1rbOgmJ96i7Mqx5+CBnwJ//O4TM=";
      aarch64-darwin = "sha256-pOBcgoyNe+Wd3MhihTyviwxj7gtpQEH+zSKDlNqH9Os=";
    }
    .${stdenv.hostPlatform.system} or "sha256-GnIe69Nt0ka/OQsrE6ykirU8rZ35SoOSnkZbl0C94MI=",
}:

buildNpmPackage rec {
  pname = "paseo";
  version = "0.15.0-smdex.2";
  # Pin the fork's verified feature revision rather than its stale release tag.

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "paseo";
    rev = "5bf8843f827fc227be2a77ab0b8185ee83b51e5e";
    hash = "sha256-kSZstBxiyOkeXLV/kp57ETcB3ep8AnTUoHp/4DO3pVU=";
  };

  nodejs = nodejs_22;

  inherit npmDepsHash;
  npmDepsFetcherVersion = 2;

  # fetchNpmDeps fetches every lockfile entry, including optional binaries for
  # other platforms. Apply the same filter before fetching and npm ci.
  # Other architectures retain the original, platform-independent cache.
  postPatch =
    lib.optionalString
      (lib.elem stdenv.hostPlatform.system [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ])
      ''
        ${python3}/bin/python3 ${./filter-lockfile.py} \
          ${if stdenv.hostPlatform.isDarwin then "darwin" else "linux"} \
          ${if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"}
      '';

  # Prevent onnxruntime-node's install script from running during automatic
  # npm rebuild (it tries to download from api.nuget.org, which fails in the
  # sandbox). We manually rebuild only node-pty in buildPhase.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    python3 # for node-gyp (node-pty compilation)
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libuv
    stdenv.cc.cc.lib
  ];

  # Don't use the default npm build hook — we need a custom build sequence
  dontNpmBuild = true;

  # Expo evaluates native version metadata even for web exports. Upstream's
  # native-version parser rejects our fork suffix; preserve it everywhere else.
  # Run after npm ci so workspace manifests and the dependency lock stay intact.
  preBuild = ''
    substituteInPlace packages/app/app.config.js \
      --replace-fail 'getNativeReleaseVersion(pkg.version)' \
      'getNativeReleaseVersion(pkg.version.replace(/-smdex(?:\.[0-9]+)?$/, ""))'
  '';

  buildPhase = ''
    runHook preBuild

    # Rebuild only node-pty (native addon for terminal emulation).
    # Speech-related native modules (sherpa-onnx-node, onnxruntime-node) are
    # intentionally left unbuilt — they're lazily loaded and gracefully
    # degrade when unavailable.
    rm -rf packages/server/node_modules/node-pty/prebuilds
    npm rebuild node-pty --workspace=@getpaseo/server
    npm run postinstall

    # Build all server packages in dependency order (defined in package.json)
    npm run build:server
    npm run build:daemon-web-ui

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Compute the daemon's runtime closure by static module-graph tracing
    # (@vercel/nft from supervisor-entrypoint.js, cli/dist/index.js, and the
    # forked terminal-worker-process.js) plus an explicit list of non-JS
    # assets read at runtime. The trace script is the single source of
    # truth for what the daemon needs at $out — auditable in plain JS, no
    # npm hoisting / .bin / workspace-symlink footguns.
    mkdir -p $out/lib/paseo
    node scripts/trace-daemon.mjs > daemon-files.txt

    while IFS= read -r path; do
      [ -z "$path" ] && continue
      mkdir -p "$out/lib/paseo/$(dirname "$path")"
      cp -a "$path" "$out/lib/paseo/$path"
    done < daemon-files.txt

    # The current upstream tracer retains the selected native addon and hooks.
    patchShebangs --build "$out/lib/paseo"
    cp -r packages/server/dist/server/web-ui $out/lib/paseo/packages/server/dist/server/

    # Root package.json lets node resolve the workspace layout when the
    # CLI/server bin starts from $out.
    cp package.json $out/lib/paseo/

    # Create wrapper for the server entry point (for systemd / direct use)
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/paseo-server \
      --add-flags "$out/lib/paseo/packages/server/dist/scripts/supervisor-entrypoint.js" \
      --set PASEO_NODE_ENV production

    # Create wrapper for the CLI
    makeWrapper ${nodejs}/bin/node $out/bin/paseo \
      --add-flags "$out/lib/paseo/packages/cli/dist/index.js" \
      --set NODE_PATH "$out/lib/paseo/node_modules"

    runHook postInstall
  '';

  passthru.category = "AI Coding Agents";

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  meta = {
    description = "Self-hosted daemon for AI coding agents (server + CLI)";
    homepage = "https://github.com/getpaseo/paseo";
    changelog = "https://github.com/smdex/paseo/commits/${src.rev}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "paseo";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
