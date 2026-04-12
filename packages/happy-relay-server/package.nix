{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchYarnDeps,
  fetchurl,
  yarnConfigHook,
  yarnInstallHook,
  nodejs,
  makeWrapper,
  versionCheckHomeHook,
  gzip,
  openssl,
  zlib,
  python3,
}:

let
  prismaEngineCommit = "c2990dca591cba766e3b7ef5d9e8a84796e47ab7";
  prismaBinaryTarget = "debian-openssl-3.0.x";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "happy-relay-server";
  version = "unstable-2026-04-12";

  src = fetchFromGitHub {
    owner = "slopus";
    repo = "happy";
    rev = "5023066963c500f333e2248c6a3989fb1e1f4836";
    hash = "sha256-c/8KSv/9PXOz/Z5A9aGw4foi0v29ATAK1qIGl6Op724=";
  };

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = "${finalAttrs.src}/yarn.lock";
    hash = "sha256-CACpq+E/a2/no9q65e/e4e4cE3+V/8xR5SYDzu1K2m0=";
  };

  prismaSchemaEngine = fetchurl {
    url = "https://binaries.prisma.sh/all_commits/${prismaEngineCommit}/${prismaBinaryTarget}/schema-engine.gz";
    hash = "sha256-bB39/jRThIewiP0hsxUhR+G9PJ0MALT8bsrkDOuoPYo=";
  };

  prismaQueryEngineLibrary = fetchurl {
    url = "https://binaries.prisma.sh/all_commits/${prismaEngineCommit}/${prismaBinaryTarget}/libquery_engine.so.node.gz";
    hash = "sha256-04CHLMihcxDG67JJ3AAPT8v7vVHdw2vrV7HtDFTG1hA=";
  };

  nativeBuildInputs = [
    nodejs
    yarnConfigHook
    yarnInstallHook
    makeWrapper
    gzip
    python3
  ];

  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    stdenv.cc.cc.lib
    openssl
    zlib
  ];

  buildPhase = ''
    runHook preBuild

    export HOME="$TMPDIR"
    export LD_LIBRARY_PATH="${
      lib.makeLibraryPath [
        stdenv.cc.cc.lib
        openssl
        zlib
      ]
    }"
    export PRISMA_ENGINES_CHECKSUM_IGNORE_MISSING=1
    export PRISMA_CLI_BINARY_TARGETS="${prismaBinaryTarget}"

    mkdir -p "$TMPDIR/prisma-engines"
    gzip -cd "${finalAttrs.prismaSchemaEngine}" > "$TMPDIR/prisma-engines/schema-engine"
    gzip -cd "${finalAttrs.prismaQueryEngineLibrary}" > "$TMPDIR/prisma-engines/libquery_engine-${prismaBinaryTarget}.so.node"
    chmod +x "$TMPDIR/prisma-engines/schema-engine"

    export PRISMA_SCHEMA_ENGINE_BINARY="$TMPDIR/prisma-engines/schema-engine"
    export PRISMA_QUERY_ENGINE_LIBRARY="$TMPDIR/prisma-engines/libquery_engine-${prismaBinaryTarget}.so.node"

    mkdir -p node_modules/@slopus packages/happy-server/node_modules/@slopus
    ln -sfn ../../packages/happy-wire node_modules/@slopus/happy-wire
    ln -sfn ../../../happy-wire packages/happy-server/node_modules/@slopus/happy-wire

    (
      cd packages/happy-server
      yarn run generate
    )

    runHook postBuild
  '';

  installPhase = ''
        runHook preInstall

    outdir="$out/libexec/happy-relay-server"
    export outdir
    mkdir -p "$outdir" "$out/bin" "$outdir/packages" "$outdir/prisma-engines" "$outdir/node_modules/@slopus"

        cp -r node_modules "$outdir/"
        rm -rf "$outdir/node_modules/.bin"

        mkdir -p "$outdir/packages/happy-server" "$outdir/packages/happy-wire"
        cp -r packages/happy-server/sources "$outdir/packages/happy-server/"
        cp -r packages/happy-server/prisma "$outdir/packages/happy-server/"
        cp packages/happy-server/package.json "$outdir/packages/happy-server/"
        cp packages/happy-server/tsconfig.json "$outdir/packages/happy-server/"

        cp -r packages/happy-wire/src "$outdir/packages/happy-wire/"
        cp packages/happy-wire/package.json "$outdir/packages/happy-wire/"
        cp packages/happy-wire/tsconfig.json "$outdir/packages/happy-wire/"

        ln -s ../../packages/happy-wire "$outdir/node_modules/@slopus/happy-wire"

        python - <<'PY'
    import os
    root = os.path.join(os.environ['outdir'], 'node_modules')
    for dirpath, dirnames, filenames in os.walk(root):
        for name in dirnames + filenames:
            path = os.path.join(dirpath, name)
            if os.path.islink(path) and not os.path.exists(path):
                os.unlink(path)
    PY

        gzip -cd "${finalAttrs.prismaQueryEngineLibrary}" > "$outdir/prisma-engines/libquery_engine-${prismaBinaryTarget}.so.node"

        makeWrapper ${nodejs}/bin/node "$out/bin/happy-relay-server" \
          --add-flags "$outdir/node_modules/tsx/dist/cli.mjs" \
          --add-flags "$outdir/packages/happy-server/sources/standalone.ts" \
          --chdir "$outdir" \
          --run 'export DATA_DIR="''${DATA_DIR:-$HOME/.happy-relay-server}"' \
          --run 'export PGLITE_DIR="''${PGLITE_DIR:-''${DATA_DIR}/pglite}"' \
          --set PRISMA_QUERY_ENGINE_LIBRARY "$outdir/prisma-engines/libquery_engine-${prismaBinaryTarget}.so.node" \
          --set LD_LIBRARY_PATH "${
            lib.makeLibraryPath [
              stdenv.cc.cc.lib
              openssl
              zlib
            ]
          }"

        runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHomeHook ];
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$(mktemp -d) "$out/bin/happy-relay-server" --help | grep -q "portable distribution"
    runHook postInstallCheck
  '';

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Relay server runtime for Happy mobile and web clients";
    homepage = "https://github.com/slopus/happy";
    changelog = "https://github.com/slopus/happy/commit/5023066963c500f333e2248c6a3989fb1e1f4836";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ ];
    mainProgram = "happy-relay-server";
    platforms = platforms.linux;
  };
})
