# CLI core of codex-chatgpt-web: the daemon/engine behind the Electron
# launcher GUI (src/cli.ts — "serve", "setup", "doctor", MCP, service).
#
# The GUI is the main package at packages/codex-chatgpt-web. Both derive from
# ONE source tree and share its state: version + src hash come from
# ../codex-chatgpt-web/hashes.json and the bun lockfile tree from
# ../codex-chatgpt-web/bun.nix, so a single update.py run (the main
# package's) moves both. This package carries no hashes.json/bun.nix of its
# own and no updater; the assert below pins the versions together at eval
# time, and packages/codex-chatgpt-web/update-companions routes CI's
# companion sweep here (update.py is a no-op checker).
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  bun2nixLib,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
  flake,
  codex-chatgpt-web,
}:

let
  # Shared with the desktop package — the single source of truth.
  versionData = builtins.fromJSON (builtins.readFile ../codex-chatgpt-web/hashes.json);
  inherit (versionData) version hash;
in
assert lib.assertMsg (version == codex-chatgpt-web.version)
  "codex-chatgpt-web-cli ${version} is out of sync with codex-chatgpt-web ${codex-chatgpt-web.version}: both read packages/codex-chatgpt-web/hashes.json — update them together via the main package's update.py";
stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "codex-chatgpt-web-cli";
  inherit version;

  src = fetchFromGitHub {
    owner = "miuuyy";
    repo = "codex-chatgpt-web";
    tag = "v${finalAttrs.version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    makeWrapper
  ];

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ../codex-chatgpt-web/bun.nix;
  };

  # The published bin is src/cli.ts run under bun — there is no bundle step.
  dontUseBunBuild = true;
  # The hook defaults, plus --production to keep devDependencies (typescript,
  # @types/*) out of the runtime closure.
  bunInstallFlags = [
    "--linker=isolated"
    "--backend=symlink"
    "--production"
  ];
  # No lifecycle scripts are needed at build time and none may run in the
  # sandbox.
  dontRunLifecycleScripts = true;

  installPhase = ''
    runHook preInstall

    # Not $out/share/codex-chatgpt-web: that is the desktop GUI's runtime
    # tree, and the two store paths must not collide when installed
    # side-by-side.
    mkdir -p $out/share/codex-chatgpt-web-cli
    cp -r src node_modules package.json tsconfig.json $out/share/codex-chatgpt-web-cli/

    makeWrapper ${lib.getExe bun} $out/bin/codex-chatgpt-web-cli \
      --add-flags "$out/share/codex-chatgpt-web-cli/src/cli.ts"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Use ChatGPT Web (including Pro) as native Codex models with context, tools, streaming and images";
    homepage = "https://github.com/miuuyy/codex-chatgpt-web";
    changelog = "https://github.com/miuuyy/codex-chatgpt-web/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "codex-chatgpt-web-cli";
    platforms = platforms.unix;
  };
})
