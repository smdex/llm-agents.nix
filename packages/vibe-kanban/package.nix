{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchurl,
  unzip,
  rustPlatform,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs-slim,
  pkg-config,
  openssl,
  libgit2,
  sqlite,
  llvmPackages,
  perl,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData)
    version
    tag
    hash
    cargoHash
    npmDepsHash
    releaseZipHash
    ;

  src = fetchFromGitHub {
    owner = "BloopAI";
    repo = "vibe-kanban";
    inherit tag;
    inherit hash;
  };

  # Upstream embeds its licensed frontend in the release binary. Extract
  # just the key for our source build; never store it in the repository.
  releaseZip = fetchurl {
    url = "https://github.com/BloopAI/vibe-kanban/releases/download/${tag}/linux-x64-vibe-kanban.zip";
    hash = releaseZipHash;
  };

  # Phase 1: Build frontend
  frontend = stdenv.mkDerivation {
    pname = "vibe-kanban-frontend";
    inherit version src;

    nativeBuildInputs = [
      nodejs-slim
      pnpm_10
      pnpmConfigHook
      unzip
    ];

    pnpmDeps = fetchPnpmDeps {
      pname = "vibe-kanban-frontend";
      inherit version src;
      pnpm = pnpm_10;
      hash = npmDepsHash;
      fetcherVersion = 3;
    };

    buildPhase = ''
      runHook preBuild

      # Extract the react-virtuoso license key from upstream's pre-built
      # release assets rather than storing it in our repository.
      export VITE_PUBLIC_REACT_VIRTUOSO_LICENSE_KEY=$(
        unzip -p ${releaseZip} vibe-kanban \
          | grep -ao 'licenseKey:"[^"]*"' \
          | head -1 \
          | cut -d'"' -f2
      )
      if [ -z "$VITE_PUBLIC_REACT_VIRTUOSO_LICENSE_KEY" ]; then
        echo "react-virtuoso license key not found in release asset" >&2
        exit 1
      fi

      # 0.1.44 reshapes the source tree into a pnpm workspace under
      # `packages/`. The local browser frontend (formerly `frontend/`)
      # now lives at `packages/local-web/` as the @vibe/local-web package.
      pnpm --filter @vibe/local-web build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r packages/local-web/dist/* $out/
      runHook postInstall
    '';
  };

in
# Phase 2: Build Rust with embedded frontend
rustPlatform.buildRustPackage {
  pname = "vibe-kanban";
  inherit version src cargoHash;

  cargoBuildFlags = [
    "--package"
    "server"
    "--package"
    "mcp"
    "--package"
    "review"
  ];

  nativeBuildInputs = [
    pkg-config
    llvmPackages.libclang
    # crates/executors enables openssl's `vendored` feature for musl
    # cross-compile builds, which forces a from-source openssl build that
    # needs perl regardless of the host openssl present in buildInputs.
    perl
  ];
  buildInputs = [
    openssl
    libgit2
    sqlite
  ];

  # Copy frontend assets before Rust build. crates/server's build.rs and
  # rust_embed both reference `../../packages/local-web/dist`.
  preBuild = ''
    mkdir -p packages/local-web/dist
    cp -r ${frontend}/* packages/local-web/dist/
  '';

  env = {
    SQLX_OFFLINE = "true";
    LIBCLANG_PATH = "${llvmPackages.libclang.lib}/lib";
  };

  doCheck = false;

  postInstall = ''
    # Upstream's `mcp` crate already declares its bin as `vibe-kanban-mcp`
    # in 0.1.44; only `server` and `review` still need renaming.
    mv $out/bin/server $out/bin/vibe-kanban
    mv $out/bin/review $out/bin/vibe-kanban-review
    rm -f $out/bin/generate_types
    rm -rf $out/bin/*.dSYM
  '';

  passthru = {
    category = "Workflow & Project Management";
    inherit frontend;
  };

  meta = {
    description = "Kanban board to orchestrate AI coding agents like Claude Code, Codex, and Gemini CLI";
    homepage = "https://github.com/BloopAI/vibe-kanban";
    changelog = "https://github.com/BloopAI/vibe-kanban/releases";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    mainProgram = "vibe-kanban";
    platforms = lib.platforms.unix;
  };
}
