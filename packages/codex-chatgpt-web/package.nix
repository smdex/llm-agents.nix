{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  bun,
  bun2nixLib,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
  mkUpdater,
  flake,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hash;
in
stdenvNoCC.mkDerivation {
  pname = "codex-chatgpt-web";
  inherit version;

  src = fetchFromGitHub {
    owner = "miuuyy";
    repo = "codex-chatgpt-web";
    tag = "v${version}";
    inherit hash;
  };

  nativeBuildInputs = [
    bun2nixLib.hook
    makeWrapper
  ];

  bunDeps = bun2nixLib.fetchBunDeps {
    bunNix = ./bun.nix;
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

    mkdir -p $out/share/codex-chatgpt-web
    cp -r src node_modules package.json tsconfig.json $out/share/codex-chatgpt-web/

    makeWrapper ${lib.getExe bun} $out/bin/codex-chatgpt-web \
      --add-flags "$out/share/codex-chatgpt-web/src/cli.ts"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "bun-github";
    purl = "pkg:github/miuuyy/codex-chatgpt-web";
  };

  meta = with lib; {
    description = "Use ChatGPT Web (including Pro) as native Codex models with context, tools, streaming and images";
    homepage = "https://github.com/miuuyy/codex-chatgpt-web";
    changelog = "https://github.com/miuuyy/codex-chatgpt-web/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "codex-chatgpt-web";
    platforms = platforms.unix;
  };
}
