{
  lib,
  flake,
  buildNpmPackage,
  fetchurl,
  formatelf,
  python3,
  stdenv,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  # koffi (a transitive dep) ships prebuilt .node files for many targets
  # (linux_x64, musl_x64, openbsd_x64, freebsd_x64, ...). autoPatchelf can't
  # satisfy foreign ones and they never run on the host anyway, so we prune
  # every target but the host's glibc build in postInstall.
  koffiArch =
    {
      x86_64 = "x64";
      aarch64 = "arm64";
      riscv64 = "riscv64d";
    }
    .${stdenv.hostPlatform.linuxArch} or stdenv.hostPlatform.linuxArch;
  koffiHostTarget = "linux_${koffiArch}";
in

buildNpmPackage rec {
  pname = "caveman-code";
  version = "0.65.2";

  # Upstream publishes a prebuilt tarball to npm (dist/cli.js is the bin), so we
  # consume that instead of driving the monorepo's native tsgo toolchain.
  src = fetchurl {
    url = "https://registry.npmjs.org/@juliusbrussee/caveman-code/-/caveman-code-${version}.tgz";
    hash = "sha256-p1U3iw45xpIoXO1SAeq0fCgUnouEzovaS12gWO9Xi6o=";
  };

  # The npm tarball ships no lockfile; vendor one next to package.nix.
  sourceRoot = "package";
  postPatch = "cp ${./package-lock.json} package-lock.json";

  npmDepsHash = "sha256-gK9qZ10y5QYtk1aBZWpOskpicHgV6cG5eGnTM9hY5V8=";

  # dist is already built upstream — only install runtime deps.
  dontNpmBuild = true;

  # onnxruntime-node's postinstall tries to fetch native binaries from
  # api.nuget.org, which the sandbox forbids. Disable all install scripts and
  # rebuild only the native addon we actually need (better-sqlite3).
  npmFlags = [ "--ignore-scripts" ];

  postConfigure = ''
    npm rebuild better-sqlite3
  '';

  postInstall = ''
    koffiBuild="$out/lib/node_modules/@juliusbrussee/caveman-code/node_modules/koffi/build/koffi"
    if [ -d "$koffiBuild" ]; then
      find "$koffiBuild" -mindepth 1 -maxdepth 1 -type d \
        ! -name "${koffiHostTarget}" -exec rm -rf {} +
    fi
  '';

  # better-sqlite3 is a native addon built via node-gyp during npm install.
  nativeBuildInputs = [
    formatelf
    python3
  ];

  # better-sqlite3 links libstdc++.
  buildInputs = [ stdenv.cc.cc.lib ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "Open-source coding agent with a terminal UI";
    homepage = "https://caveman.so/";
    changelog = "https://github.com/JuliusBrussee/caveman-code/releases";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "caveman-code";
    platforms = platforms.unix;
  };
}
