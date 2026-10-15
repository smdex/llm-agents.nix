{
  lib,
  stdenv,
  flake,
  fetchFromGitHub,
  fetchurl,
  rustPlatform,
  makeBinaryWrapper,
  alsa-lib,
  openssl,
  pkg-config,
}:

let
  # octopus-code-mode-engine depends on deno_core, whose rusty_v8 build
  # script downloads a prebuilt static V8 library. Point it at a Nix fetch
  # so the build stays offline.
  librustyV8Version = "149.2.0";
  librustyV8 = fetchurl {
    url = "https://github.com/denoland/rusty_v8/releases/download/v${librustyV8Version}/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a.gz";
    hash =
      {
        x86_64-linux = "sha256-iu2YY323533Iv7i7R1nsW95HLQv3lD9Y4OYqNQlFxVk=";
        aarch64-linux = "sha256-+XdRJ8pk3MSjZi0BpSGizvuluY+DOUOog9hHc7Kv88U=";
        x86_64-darwin = "sha256-eUlAo4o/ZrfvUqXwA8awlPdDrQQKZK+z082frUlADwc=";
        aarch64-darwin = "sha256-+rsuyNO6Wm3qY9uaNalg3FypheujLzQrm6Sqocc0sv4=";
      }
      .${stdenv.hostPlatform.system}
        or (throw "librusty_v8 ${librustyV8Version} prebuilt is not available for ${stdenv.hostPlatform.system}");
  };
in

rustPlatform.buildRustPackage rec {
  pname = "octopus-si-os";
  # Upstream has no tags yet; workspace version is 0.1.0 and we track an
  # unstable rev of the fork.
  version = "0.1.0-unstable-2026-10-14";

  src = fetchFromGitHub {
    owner = "maximoffua";
    repo = "Octopus-SI-OS";
    rev = "8e049ae63139b1fa118da35a34e2c22d3b597abf";
    hash = "sha256-bnVDnO2y9+ni0EXYWwmyVhvx6oF6kS3aUt+6L8D8a0g=";
  };

  cargoHash = "sha256-FsmvHJTd2YLpEI+2qn1aQ7UzUTDAZY+e9K6IymQvVe4=";

  env.RUSTY_V8_ARCHIVE = librustyV8;

  # Several registry crates use reqwest with default (native-tls) features.
  nativeBuildInputs = [
    makeBinaryWrapper
    pkg-config
  ];
  buildInputs = [
    alsa-lib
    openssl
  ];

  # Upstream CI runs targeted `cargo test -p <crate>` suites per check; the
  # full workspace test suite (long-running integration + doomsday tests) is
  # too heavy for a build sandbox.
  doCheck = false;

  # The runtime resolves its installation as <root>/bin/octopus plus
  # <root>/registry (unless OCTOPUS_INSTALLATION_ROOT is set). Lay the source
  # registry out in share/ next to a bin symlink and wrap the entry point.
  postInstall = ''
    mkdir -p $out/libexec/octopus-si-os $out/share/octopus-si-os
    mv $out/bin/octopus $out/libexec/octopus-si-os/octopus
    ln -s ../../bin $out/share/octopus-si-os/bin
    cp -r registry $out/share/octopus-si-os/registry

    makeBinaryWrapper $out/libexec/octopus-si-os/octopus $out/bin/octopus \
      --set-default OCTOPUS_INSTALLATION_ROOT $out/share/octopus-si-os
  '';

  # The runtime has no --version flag and `doctor` expects an already-synced
  # Home registry (and spawns long-lived life-probe children), so smoke-check
  # the wrapper by invoking it bare: usage goes to stderr with exit 2.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    ( $out/bin/octopus 2>&1 || true ) | grep -q "boot the OS"

    runHook postInstallCheck
  '';

  passthru.category = "AI Coding Agents";

  meta = {
    description = "Agentic OS: runtime daemon and registry of the Octopus Superintelligence OS";
    homepage = "https://github.com/maximoffua/Octopus-SI-OS";
    changelog = "https://github.com/maximoffua/Octopus-SI-OS/commits/${src.rev}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "octopus";
    platforms = lib.platforms.unix;
  };
}
