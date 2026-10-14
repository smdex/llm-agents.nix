{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
  perl,
  lld,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "cass";
  version = "0.10.0";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "coding_agent_session_search";
    tag = "v${version}";
    hash = "sha256-7spfk9GwgmF9+yEUG4waMsPILzVOjCaHio9OxnquIhk=";
  };

  cargoHash = "sha256-RMiGL8fbi2T5tY6fLEkmlyJIKDD7vZIzV3OdE5LXETY=";

  # Dependencies are now registry crates. Patch the extracted vendor tree,
  # retaining the scalar fallback for intrinsics unsupported by stable Rust.
  cargoDeps =
    (rustPlatform.fetchCargoVendor {
      inherit src;
      hash = cargoHash;
      name = "cass-${version}-vendor";
    }).overrideAttrs
      (old: {
        buildCommand = old.buildCommand + ''
          frankentorchKernel=$(find "$out" -path '*/frankentorch-kernel-cpu-*/src/lib.rs' -print -quit)
          test -n "$frankentorchKernel"
          sed -i '/if std::arch::is_x86_feature_detected!("avx512vnni")/i\        #[cfg(any())]' "$frankentorchKernel"
          sed -i '/target_feature(enable = "avx512vnni,avx512bw,avx512f")/i\#[cfg(any())]' "$frankentorchKernel"
        '';
      });

  nativeBuildInputs = [
    pkg-config
    perl
    lld
  ];
  buildInputs = [ openssl ];

  # Upstream requires nightly Rust. RUSTC_BOOTSTRAP enables the one nightly
  # asupersync feature needed by the locked dependency graph on nixpkgs Rust.
  env.RUSTC_BOOTSTRAP = 1;

  # Only ship the user-facing binary; upstream's other binaries are test tools.
  cargoBuildFlags = [
    "--bin"
    "cass"
  ];

  # Upstream's integration suite requires local coding-agent history and a
  # writable home directory, neither of which is available in the Nix sandbox.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "Memory & Code Intelligence";

  meta = with lib; {
    description = "Search local coding agent session history across providers";
    homepage = "https://github.com/Dicklesworthstone/coding_agent_session_search";
    changelog = "https://github.com/Dicklesworthstone/coding_agent_session_search/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "cass";
    platforms = platforms.all;
  };
}
