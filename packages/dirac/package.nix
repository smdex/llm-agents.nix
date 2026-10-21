{
  lib,
  flake,
  buildNpmPackage,
  fetchurl,
  mkUpdater,
  ripgrep,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  data = lib.importJSON ./hashes.json;
in
buildNpmPackage rec {
  pname = "dirac";
  inherit (data) version;

  # Upstream publishes a prebuilt tarball to npm (dist/cli.mjs is the bin), so
  # consume that instead of driving the heavy VSCode-extension monorepo's
  # native toolchain (esbuild, protobuf, wasm).
  src = fetchurl {
    url = "https://registry.npmjs.org/dirac-cli/-/dirac-cli-${version}.tgz";
    hash = data.sourceHash;
  };

  # The npm tarball ships no lockfile; vendor one next to package.nix.
  # It also references man/dirac.1 which is absent from the tarball, so stub it.
  sourceRoot = "package";
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    mkdir -p man
    cp ${./dirac.1} man/dirac.1
  '';

  inherit (data) npmDepsHash;

  # dist is already built upstream — only install runtime deps.
  dontNpmBuild = true;

  # @vscode/ripgrep's postinstall tries to fetch a prebuilt rg binary from the
  # network, which the sandbox forbids. Skip all install scripts; we drop in a
  # real ripgrep from nixpkgs in postInstall instead.
  npmFlags = [ "--ignore-scripts" ];

  postInstall = ''
    rgDir="$out/lib/node_modules/dirac-cli/node_modules/@vscode/ripgrep/bin"
    mkdir -p "$rgDir"
    ln -s ${lib.getExe ripgrep} "$rgDir/rg"
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";
  passthru.updater = mkUpdater {
    kind = "npm";
    purl = "pkg:npm/dirac-cli";
  };

  meta = with lib; {
    description = "Open-source AI coding agent focused on efficiency and context curation";
    homepage = "https://dirac.run";
    changelog = "https://github.com/dirac-run/dirac/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "dirac";
    platforms = platforms.unix;
  };
}
