{
  lib,
  flake,
  fetchFromGitHub,
  rustPlatform,
  makeWrapper,
  pkg-config,
  patchelf,
  alsa-lib,
  fontconfig,
  freetype,
  libxkbcommon,
  libxcb,
  vulkan-loader,
  wayland,
  wl-clipboard,
  xclip,
}:

# GPUI's Linux backend is the only one built here; macOS users install the
# signed DMG or the Homebrew cask from the fork instead.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "herdr-gpui";
  # Calendar version carried by the fork's CI (HERDR_RELEASE_VERSION); the
  # fork publishes no tags, so this pin tracks verified fork main revisions.
  version = "20261031.3";
  env.HERDR_RELEASE_VERSION = finalAttrs.version;

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "herdr-gpui";
    rev = "1eb92cf445189c698bb7fce69c738a93f4f2192c";
    hash = "sha256-CX/59E26D8xH8Y2c7xsr2P+m9UZlv2El+Gmre7lAYRE=";
  };

  cargoHash = "sha256-QCoRD4sYWSeZsTkHAyuKPWzhA37COAuKUbSsjvOd8k0=";

  outputs = [
    "out"
    "acp"
    "remoteControl"
    "automate"
  ];

  # The app starts chats with the herdr-acp beside its executable, runs the
  # herdr-remote-control beside it as a user service, and runs automations in
  # the herdr-automate there. Bluetooth discovery uses herdr-nearby beside it.
  cargoBuildFlags = [
    "-p"
    "herdr-gpui"
    "-p"
    "herdr-acp"
    "-p"
    "herdr-remote-control"
    "-p"
    "herdr-automate"
    "-p"
    "herdr-nearby"
  ];

  nativeBuildInputs = [
    makeWrapper
    pkg-config
    patchelf
    rustPlatform.bindgenHook
  ];

  # Loaded with dlopen at runtime, so the linker never records them.
  runtimeLibraries = [
    vulkan-loader
    wayland
  ];

  buildInputs = [
    alsa-lib
    fontconfig
    freetype
    libxkbcommon
    libxcb
  ]
  ++ finalAttrs.runtimeLibraries;

  # The workspace test suite needs a desktop session and a live daemon.
  doCheck = false;

  postInstall = ''
    # Real copies keep current_exe beside the bundle's companions.
    install -Dm755 $out/bin/herdr-acp $acp/bin/herdr-acp
    install -Dm755 $out/bin/herdr-remote-control $remoteControl/bin/herdr-remote-control
    install -Dm755 $out/bin/herdr-automate $automate/bin/herdr-automate
    # The remote daemon discovers ACP beside its own real executable.
    ln -s $acp/bin/herdr-acp $remoteControl/bin/herdr-acp
    install -Dm644 scripts/release/so.pen.herdr-gpui.desktop \
      $out/share/applications/so.pen.herdr-gpui.desktop
    install -Dm644 assets/icons/herdr-linux.svg \
      $out/share/icons/hicolor/scalable/apps/herdr-gpui.svg
  '';

  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath finalAttrs.runtimeLibraries} $out/bin/herdr-gpui
    wrapProgram $out/bin/herdr-gpui \
      --prefix PATH : ${
        lib.makeBinPath [
          wl-clipboard
          xclip
        ]
      }
  '';

  # Every build runs each shipped program's safe CLI and checks ldd, as the
  # release smoke test does, so a package missing a companion or linking
  # outside the store fails to build. Each check prints and exits before any
  # UI, socket, or daemon starts; a wrapper that still runs the real program
  # passes too.
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    for program in herdr-gpui herdr-acp herdr-remote-control herdr-automate herdr-nearby; do
      test -x "$out/bin/$program"
      # Capture before matching: with pipefail, grep -q exiting early
      # would fail the writer with SIGPIPE (as the release smoke notes).
      linked=$(ldd "$out/bin/$program" 2>/dev/null || true)
      if grep "not found" <<<"$linked"; then
        echo "$program has libraries the output does not carry" >&2
        exit 1
      fi
    done
    $out/bin/herdr-gpui --help >/dev/null
    $out/bin/herdr-acp --help >/dev/null
    $out/bin/herdr-remote-control --version >/dev/null
    $out/bin/herdr-automate --version >/dev/null
    test "$($out/bin/herdr-nearby --version)" = "herdr-nearby ${finalAttrs.version}"
    $acp/bin/herdr-acp --help >/dev/null
    $remoteControl/bin/herdr-remote-control --version >/dev/null
    $remoteControl/bin/herdr-acp --help >/dev/null
    test "$($automate/bin/herdr-automate --version)" = "herdr-automate ${finalAttrs.version}"
    for standalone in "$acp" "$remoteControl" "$automate"; do
      test ! -e "$standalone/bin/herdr-gpui"
      # A split output must not retain the bundle through ELF RPATHs.
      if grep -r -a -l -F "$out" "$standalone"; then
        echo "standalone output references the GUI bundle" >&2
        exit 1
      fi
    done
    runHook postInstallCheck
  '';

  passthru.category = "Workflow & Project Management";

  meta = {
    description = "Native GPUI client for an existing local Herdr daemon (smdex fork)";
    homepage = "https://herdrui.dev";
    changelog = "https://github.com/smdex/herdr-gpui/commits/${finalAttrs.src.rev}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "herdr-gpui";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
