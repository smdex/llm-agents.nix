{
  lib,
  stdenv,
  platformSource,
  makeWrapper,
  openssl,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
    };
    urlTemplate = "https://github.com/happier-dev/happier/releases/download/cli-stable/happier-{platform}.tar.gz";
  };
  libPath = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    openssl
  ];
in
stdenv.mkDerivation {
  pname = "happier";
  inherit (source) version src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  # The entry point is a Bun compiled executable. Its bytecode payload is
  # appended to the ELF, so stripping or autoPatchelfHook would corrupt it.
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/happier $out/bin
    cp -a . $out/lib/happier
    bin=$out/lib/happier/happier

    # Bun's compiled payload is appended to this executable. Do not mutate it:
    # a wrapper keeps the binary byte-for-byte intact while exposing dynamic
    # libraries needed by dlopen'd native addons.
    makeWrapper "$bin" $out/bin/happier \
      --prefix LD_LIBRARY_PATH : "${libPath}"

    runHook postInstall
  '';

  doInstallCheck = false;

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
