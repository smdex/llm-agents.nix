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
  version = "0.6.23";

  src = fetchFromGitHub {
    owner = "Dicklesworthstone";
    repo = "coding_agent_session_search";
    tag = "v${version}";
    hash = "sha256-buUYbiaWZjp99DXG+HRO+zCY0cOJz5bH8qEJnu0HZa8=";
  };

  cargoHash = "sha256-GOIvNTkZWqjt1S/Kj67PknokpK61ADyLUCFaRRgZMtw=";

  # The frankensearch git dependency lists an optimization-only workspace
  # member that refers to an absent sibling checkout. It is not a dependency
  # of cass, but removing it lets Nix inspect and vendor the locked crates.
  # rustc 1.97 also fails to compile frankentorch's AVX-512 VNNI intrinsics;
  # disable that optional runtime optimization and retain its scalar fallback.
  # Locate both files by content/path rather than revision so nix-update can
  # update the locked dependency graph without hand-editing this expression.
  depsExtraArgs.postBuild = ''
    frankensearchManifest=$(grep -rlF '"tools/optimize_params",' "$out/git" --include Cargo.toml)
    test -n "$frankensearchManifest"
    sed -i '/"tools\/optimize_params",/d' "$frankensearchManifest"

    frankentorchKernel=$(find "$out/git" -path '*/crates/ft-kernel-cpu/src/lib.rs' -print -quit)
    test -n "$frankentorchKernel"
    sed -i '/if std::arch::is_x86_feature_detected!("avx512vnni")/i\        #[cfg(any())]' "$frankentorchKernel"
    sed -i '/target_feature(enable = "avx512vnni,avx512bw,avx512f")/i\#[cfg(any())]' "$frankentorchKernel"
  '';

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
