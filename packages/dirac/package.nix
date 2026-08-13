{
  lib,
  flake,
  buildNpmPackage,
  fetchurl,
  autoPatchelfHook,
  stdenv,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildNpmPackage rec {
  pname = "dirac";
  version = "0.4.35";

  # Upstream ships a prebuilt tarball to npm (dist/cli.mjs is the bin); avoid
  # the VSCode-extension monorepo's heavy native toolchain entirely.
  src = fetchurl {
    url = "https://registry.npmjs.org/dirac-cli/-/dirac-cli-${version}.tgz";
    hash = "sha256-1sirutiR5bHOaDmWU8u06qNEtoKx6zsI2nO83wnunTE=";
  };

  # The npm tarball ships no lockfile; vendor one next to package.nix. The
  # tarball also omits the man/ page that package.json's "man" field points
  # at, so create a stub so npmInstallHook's man copy does not fail.
  sourceRoot = "package";
  postPatch = ''
    cp ${./package-lock.json} package-lock.json
    mkdir -p man
    touch man/dirac.1
  '';

  npmDepsHash = "sha256-htnHWhVrYCZ3DlZ1k2lwUeqSUBG9BIzBfPy/xbp+ptY=";

  # dist is already built upstream — only install runtime deps.
  dontNpmBuild = true;

  # @vscode/ripgrep's postinstall fetches a binary from GitHub; the platform
  # package (@vscode/ripgrep-linux-x64) already ships a prebuilt rg, so skip all
  # install scripts and let autoPatchelfHook fix up the bundled native rg.
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [
    autoPatchelfHook
  ];

  # sharp (@img/sharp-linux-x64) and libvips link libstdc++/libgcc_s.
  buildInputs = [ stdenv.cc.cc.lib ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Open-source autonomous coding agent CLI (Cline fork) focused on efficiency and context curation";
    homepage = "https://dirac.run";
    changelog = "https://github.com/dirac-run/dirac/releases";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "dirac";
    platforms = platforms.unix;
  };
}
