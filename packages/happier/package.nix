{
  lib,
  stdenv,
  platformSource,
  makeWrapper,
  formatelf,
  openssl,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
    };
    urlTemplate = "https://github.com/happier-dev/happier/releases/download/cli-stable/happier-v{version}-{platform}.tar.gz";
  };
  libPath = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    openssl
  ];
in
stdenv.mkDerivation {
  pname = "happier";
  inherit (source) version src;

  nativeBuildInputs = [
    formatelf
    makeWrapper
  ];
  buildInputs = [
    stdenv.cc.cc.lib
    openssl
  ];

  dontBuild = true;
  # Preserve Bun's appended bytecode while formatelf fixes the ELF loader.
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/happier $out/bin
    cp -a . $out/lib/happier
    # These glibc builds cannot load the bundled optional musl addons.
    find $out/lib/happier/node_modules -iname '*musl*' -prune -exec rm -rf {} +
    bin=$out/lib/happier/happier

    # Native addons use dlopen rather than the main binary's RUNPATH.
    makeWrapper "$bin" $out/bin/happier \
      --prefix LD_LIBRARY_PATH : "${libPath}"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "End-to-end encrypted cross-device companion for coding agents";
    homepage = "https://github.com/happier-dev/happier";
    changelog = "https://github.com/happier-dev/happier/releases/tag/cli-stable";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "happier";
    platforms = source.platforms;
    maintainers = with lib.maintainers; [ ];
  };
}
