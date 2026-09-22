{
  lib,
  stdenv,
  fetchFromGitHub,
  buildNpmPackage,
  nodejs_22,
  python3,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
  # node-pty needs libuv headers on Linux
  libuv,
  # Exposed so downstream flakes that follow a different nixpkgs revision
  # (where `fetchNpmDeps` may produce a different hash for the same lockfile)
  # can override via `.override { npmDepsHash = "sha256-..."; }` without
  # `overrideAttrs` gymnastics.
  npmDepsHash ? "sha256-3cqO8DpPVDjYaSh0q5EPJuMpCgl2OJ17uLGVGuk1Wwc=",
}:

buildNpmPackage rec {
  pname = "paseo";
  version = "0.9.0";

  src = fetchFromGitHub {
    owner = "getpaseo";
    repo = "paseo";
    tag = "v${version}";
    hash = "sha256-qCjsMOi9/vMp0AVuWeSoiS1bv4bFMKoAha/zWNb2fHE=";
  };

  nodejs = nodejs_22;

  inherit npmDepsHash;

  # Prevent onnxruntime-node's install script from running during automatic
  # npm rebuild (it tries to download from api.nuget.org, which fails in the
  # sandbox). We manually rebuild only node-pty in buildPhase.
  npmRebuildFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    python3 # for node-gyp (node-pty compilation)
    makeWrapper
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libuv ];

  # Don't use the default npm build hook — we need a custom build sequence
  dontNpmBuild = true;

  buildPhase = ''
    runHook preBuild

    # Rebuild only node-pty (native addon for terminal emulation).
    # Speech-related native modules (sherpa-onnx-node, onnxruntime-node) are
    # intentionally left unbuilt — they're lazily loaded and gracefully
    # degrade when unavailable.
    npm rebuild node-pty

    # Build all server packages in dependency order (defined in package.json)
    npm run build:server

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

    # Ship the complete node-pty package(s), including the addon compiled by
    # `npm rebuild node-pty`. nft cannot trace its load path — utils.js probes
    # build/Release and prebuilds/<platform> at runtime — and in this npm
    # workspace layout node-pty is installed under packages/server/node_modules,
    # so the trace script's root-level `node_modules/node-pty/prebuilds` pin
    # matches nothing. Replace whatever the trace copied with the full tree.
    find node_modules packages -type d -name node-pty | while read -r ptyDir; do
      rel="''${ptyDir#./}"
      target="$out/lib/paseo/$rel"
      rm -rf "$target"
      mkdir -p "$(dirname "$target")"
      cp -a "$ptyDir" "$target"
    done

    # Root package.json lets node resolve the workspace layout when the
    # CLI/server bin starts from $out.
    cp package.json $out/lib/paseo/

    # Create wrapper for the server entry point (for systemd / direct use)
    mkdir -p $out/bin
    makeWrapper ${nodejs}/bin/node $out/bin/paseo-server \
      --add-flags "$out/lib/paseo/packages/server/dist/scripts/supervisor-entrypoint.js" \
      --set NODE_ENV production

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
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v${version}";
    license = lib.licenses.agpl3Plus;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with lib.maintainers; [ ];
    mainProgram = "paseo";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
}
