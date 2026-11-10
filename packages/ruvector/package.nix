{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  versionCheckHook,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "ruvector";
  version = "0.2.40";

  src = fetchFromGitHub {
    owner = "ruvnet";
    repo = "RuVector";
    tag = "ruvector-v${finalAttrs.version}";
    hash = "sha256-iDxv6EZj7+xhWQ1RwrvT9F/fG0BVh92VTKmSK8HHYfI=";
  };

  cargoHash = "sha256-t2ddp4OQ+knTlhIW/FGhDyG7lUdkPA/I7OENi4ps8zw=";

  # Upstream's release tags (ruvector-vX.Y.Z) are a separate version train
  # from the Cargo workspace version (2.3.0 at this tag); CI only stamps the
  # tag version into the npm release artifacts. The built binary reports the
  # crate's own Cargo version, so override the version at the three surfaces
  # the CLI crate exposes (clap --version for both binaries and the MCP
  # initialize handshake) to match the release tag version.
  postPatch = ''
    substituteInPlace crates/ruvector-cli/src/main.rs \
      --replace-fail '#[command(version)]' '#[command(version = "${finalAttrs.version}")]'
    substituteInPlace crates/ruvector-cli/src/mcp_server.rs \
      --replace-fail '#[command(version)]' '#[command(version = "${finalAttrs.version}")]'
    substituteInPlace crates/ruvector-cli/src/mcp/handlers.rs \
      --replace-fail 'env!("CARGO_PKG_VERSION")' '"${finalAttrs.version}"'
  '';

  # The workspace has ~130 members (the pgrx extension and RVF surfaces are
  # excluded upstream); scope the build to the CLI crate, which produces the
  # `ruvector` and `ruvector-mcp` binaries.
  cargoBuildFlags = [
    "--frozen"
    "-p"
    "ruvector-cli"
  ];

  # The workspace test suite is heavy (property/graph suites); not necessary
  # for packaging.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Utilities";

  meta = with lib; {
    description = "High-performance Rust vector database with CLI and MCP server";
    homepage = "https://github.com/ruvnet/RuVector";
    changelog = "https://github.com/ruvnet/RuVector/releases/tag/ruvector-v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "ruvector";
    platforms = platforms.unix;
  };
})
