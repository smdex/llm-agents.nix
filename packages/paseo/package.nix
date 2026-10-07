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
  npmDepsHash ? "sha256-3dZg3fd8x4Y5knKiekzWLMmw7FEZDEzTjwa1dJiLT+U=",
}:

buildNpmPackage rec {
  pname = "paseo";
  version = "0.11.0-beta.2";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "paseo";
    tag = "v${version}";
    hash = "sha256-1po2t3DwCpFqppHGxB1r3GpDHHYMRhpxcEmoTJPVCjs=";
  };

  nodejs = nodejs_22;

  inherit npmDepsHash;
  npmDepsFetcherVersion = 2;

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
    changelog = "https://github.com/smdex/paseo/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "paseo";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
