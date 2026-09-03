{
  lib,
  flake,
  buildNpmPackage,
  fetchurl,
  ripgrep,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildNpmPackage rec {
  pname = "dirac";
  version = "0.4.35";

  # Upstream publishes a prebuilt tarball to npm (dist/cli.mjs is the bin), so
  # consume that instead of driving the heavy VSCode-extension monorepo's
  # native toolchain (esbuild, protobuf, wasm).
  src = fetchurl {
    url = "https://registry.npmjs.org/dirac-cli/-/dirac-cli-${version}.tgz";
    hash = "sha256-1sirutiR5bHOaDmWU8u06qNEtoKx6zsI2nO83wnunTE=";
  };

  # The npm tarball ships no lockfile; vendor one next to package.nix.
  # It also references man/dirac.1 which is absent from the tarball, so stub it.
  sourceRoot = "package";
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    mkdir -p man
    cp ${./dirac.1} man/dirac.1
  '';

  npmDepsHash = "sha256-I0mFIBjvSV0Mt5ouVKiLmtd4JYvTtMcNW7aGBCmma68=";

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
