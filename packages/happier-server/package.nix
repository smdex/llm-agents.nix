{
  lib,
  stdenv,
  platformSource,
  mkUpdater,
  makeWrapper,
  formatelf,
  openssl,
}:

let
  source = platformSource {
    hashesFile = ./hashes.json;
    platforms = {
      x86_64-linux = "linux-x64";
    };
    urlTemplate = "https://github.com/happier-dev/happier/releases/download/server-stable/happier-server-v{version}-{platform}.tar.gz";
  };
  libPath = lib.makeLibraryPath [
    stdenv.cc.cc.lib
    openssl
  ];
in
stdenv.mkDerivation {
  pname = "happier-server";
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
  # The server executable is a Bun compiled binary; preserve its appended
  # payload and the full sibling bundle (Prisma engines, UI, migrations).
  dontStrip = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/happier-server $out/bin
    cp -a . $out/lib/happier-server
    # These glibc builds cannot load the bundled optional musl addons.
    find $out/lib/happier-server/node_modules -iname '*musl*' -prune -exec rm -rf {} +
    bin=$out/lib/happier-server/happier-server

    # Prisma's native engine is loaded dynamically rather than via RUNPATH.
    makeWrapper "$bin" $out/bin/happier-server \
      --prefix LD_LIBRARY_PATH : "${libPath}" \
      --set PRISMA_QUERY_ENGINE_LIBRARY "$out/lib/happier-server/generated/sqlite-client/libquery_engine-debian-openssl-3.0.x.so.node"

    runHook postInstall
  '';

  passthru = {
    category = "AI Assistants";
    updater = mkUpdater (
      source.updater
      // {
        versionSource = {
          type = "text";
          url = "https://api.github.com/repos/happier-dev/happier/releases/tags/server-stable";
          regex = ''"name"\s*:\s*"happier-server-v([0-9.]+)-linux-x64\.tar\.gz"'';
        };
      }
    );
  };

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
