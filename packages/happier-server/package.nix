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
    urlTemplate = "https://github.com/happier-dev/happier/releases/download/server-stable/happier-server-{platform}.tar.gz";
  };
  libPath = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    openssl
  ];
in
stdenv.mkDerivation {
  pname = "happier-server";
  inherit (source) version src;

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  # The server executable is a Bun compiled binary; preserve its appended
  # payload and the full sibling bundle (Prisma engines, UI, migrations).
  dontStrip = true;
  dontPatchELF = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/happier-server $out/bin
    cp -a . $out/lib/happier-server
    bin=$out/lib/happier-server/happier-server

    # Bun's compiled payload is appended to this executable. Do not mutate it:
    # a wrapper keeps the binary byte-for-byte intact while exposing dynamic
    # libraries needed by the packaged Prisma engine.
    makeWrapper "$bin" $out/bin/happier-server \
      --prefix LD_LIBRARY_PATH : "${libPath}" \
      --set PRISMA_QUERY_ENGINE_LIBRARY "$out/lib/happier-server/generated/sqlite-client/libquery_engine-debian-openssl-3.0.x.so.node"

    runHook postInstall
  '';

  passthru.category = "AI Assistants";

  meta = {
    description = "Self-hosted, end-to-end encrypted Happier sync server";
    homepage = "https://github.com/happier-dev/happier";
    changelog = "https://github.com/happier-dev/happier/releases/tag/server-stable";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    mainProgram = "happier-server";
    platforms = source.platforms;
    maintainers = with lib.maintainers; [ ];
  };
}
