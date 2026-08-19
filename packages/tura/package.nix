{
  lib,
  flake,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  pkg-config,
  unpinCargoMsrvHook,
  versionCheckHook,
  openssl,
  gtk3,
  libappindicator,
  xdotool,
  libxkbcommon,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "tura";
  version = "0.1.37";

  src = fetchFromGitHub {
    owner = "Tura-AI";
    repo = "tura";
    tag = "v${finalAttrs.version}";
    hash = "sha256-6LdMhIV2Ly/vX24wAU6nllTto5qvhBoZi9blgqLxYHY=";
  };

  cargoHash = "sha256-kLwEIvl/SjRlsmd7amre/zNyb9b3l+lcHc9MOe8LDEw=";

  # The Rust CLI has no --version flag; add one so versionCheckHook can
  # verify the packaged release.
  patches = [ ./cli-version-flag.patch ];

  postPatch = ''
    rm rust-toolchain.toml
    # Upstream leaves the workspace Cargo version at 0.1.0 even for tagged
    # releases (the npm wrapper carries 0.1.37 from package.json), so align
    # CARGO_PKG_VERSION with the release tag. Cargo rewrites Cargo.lock for
    # workspace members during the offline build.
    substituteInPlace Cargo.toml \
      --replace-fail 'version = "0.1.0"' 'version = "${finalAttrs.version}"'
  '';

  env = {
    # Matches upstream release builds (scripts/build-release.sh); surfaces in
    # the version handshake as "<version>+release".
    TURA_BUILD_KIND = "release";
  };

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    unpinCargoMsrvHook
  ];

  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    # gateway links tao + tray-icon (system tray), which pull the GTK stack.
    gtk3
    libappindicator
    xdotool
    libxkbcommon
  ];

  # Build the same binaries scripts/build-release.sh ships: the CLI front
  # (tura_exec), backend services, and the Rust command tools. Plain --package
  # builds would also build runtime's mock_router_for_test helper binary.
  cargoBuildFlags = map (bin: "--bin=${bin}") [
    "tura_exec"
    "tura_gateway"
    "tura_router"
    "tura_session_db"
    "tura_runtime"
    "tura-command-generate-media"
    "tura-command-read-media"
    "tura-command-web-discover"
  ];

  # Tests need live providers, network access, and OS fixtures.
  doCheck = false;

  postInstall = ''
    share=$out/share/tura

    # Mirror the runtime resources that scripts/build-release.sh stages next to
    # the binaries (copy_release_config + copy_release_runtime_files): agents,
    # personas, prompt manuals, tool manifests, command packages, and the
    # provider config. CARGO_MANIFEST_DIR paths baked in at build time do not
    # exist at runtime; the services resolve these through TURA_PROJECT_ROOT.
    install -Dm644 crates/provider/config/provider_config.json \
      $share/config/provider_config.json
    mkdir -p $share/agents $share/personas $share/crates/runtime/src $share/crates/tools/src/command_run
    cp -R agents/src $share/agents/src
    cp -R personas/src $share/personas/src
    cp -R crates/runtime/src/runtime_prompt $share/crates/runtime/src/runtime_prompt
    cp -R crates/tools/src/commands $share/crates/tools/src/commands
    cp crates/tools/src/command_run/schema.json $share/crates/tools/src/command_run/schema.json
    mkdir -p $share/commands
    for command in generate_media read_media web_discover; do
      cp -R commands/$command $share/commands/$command
    done
    find $share \( \
      -name .venv -o -name tests -o -name target -o -name node_modules \
      -o -name __pycache__ -o -name .pytest_cache \
    \) -type d -prune -exec rm -rf {} +

    # Ship the CLI under the user-facing `tura` name, like the npm wrapper;
    # tura_exec was formerly called tura and stays available as an alias.
    mv $out/bin/tura_exec $out/bin/tura

    # Point the binaries at the packaged runtime root, mirroring the env the
    # npm launcher (npm/tura.mjs) sets for the release directory.
    for binary in $out/bin/*; do
      wrapProgram $binary \
        --set-default TURA_PROJECT_ROOT $share \
        --set-default TURA_PROVIDER_CONFIG $share/config/provider_config.json
    done

    ln -s tura $out/bin/tura_exec
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Local AI coding system - Rust CLI and backend services";
    homepage = "https://turaai.net";
    changelog = "https://github.com/Tura-AI/tura/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Plus;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "tura";
    platforms = lib.platforms.unix;
  };
})
