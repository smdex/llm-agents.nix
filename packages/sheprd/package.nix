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
  pname = "sheprd";
  # Release tag from the sheprd-labs/sheprd rename; published as the smdex
  # fork tag on GitHub and mirrored to gitlab smaximov/sheprd.
  version = "20261112.1-smdex.2";
  # The source's release_version::numeric() only accepts YYYYMMDD.COUNTER;
  # a fork-suffixed value is rejected as malformed, so the env stamps the
  # upstream release base while the nix version identifies the fork tag.
  env.HERDR_RELEASE_VERSION = "20261112.1";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "herdr-gpui";
    tag = "v${finalAttrs.version}";
    hash = "sha256-kwLC9VW4FHOB6RgUX30EFXcdQLytqMeuoY0RjCI5JdM=";
  };

  cargoHash = "sha256-WZv1lGiMVcIBmBbg2wIkJR0qdeN531yrbj77sykNvL0=";

  outputs = [
    "out"
    "acp"
    "remoteControl"
    "automate"
  ];

  # The app starts chats with the sheprd-acp beside its executable (looking
  # up the herdr-acp name), runs the sheprd-remote-control beside it as a
  # user service, runs automations in the sheprd-automate there, and starts
  # sheprd-nearby for Bluetooth discovery beside it.
  cargoBuildFlags = [
    "-p"
    "sheprd-gpui"
    "-p"
    "sheprd-acp"
    "-p"
    "sheprd-remote-control"
    "-p"
    "sheprd-automate"
    "-p"
    "sheprd-nearby"
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
    install -Dm755 $out/bin/sheprd-acp $acp/bin/sheprd-acp
    install -Dm755 $out/bin/sheprd-remote-control $remoteControl/bin/sheprd-remote-control
    install -Dm755 $out/bin/sheprd-automate $automate/bin/sheprd-automate
    # The remote daemon discovers ACP beside its own real executable.
    ln -s $acp/bin/sheprd-acp $remoteControl/bin/sheprd-acp
    ln -s $acp/bin/sheprd-acp $remoteControl/bin/herdr-acp
    # Installed configs and older setups keep the herdr-* command names.
    ln -s sheprd $out/bin/herdr-gpui
    ln -s sheprd-acp $out/bin/herdr-acp
    ln -s sheprd-remote-control $out/bin/herdr-remote-control
    ln -s sheprd-automate $out/bin/herdr-automate
    ln -s sheprd-nearby $out/bin/herdr-nearby
    ln -s sheprd-acp $acp/bin/herdr-acp
    ln -s sheprd-remote-control $remoteControl/bin/herdr-remote-control
    ln -s sheprd-automate $automate/bin/herdr-automate
    install -Dm644 scripts/release/org.sheprd.Sheprd.desktop \
      $out/share/applications/org.sheprd.Sheprd.desktop
    install -Dm644 assets/icons/sheprd-linux.svg \
      $out/share/icons/hicolor/scalable/apps/sheprd.svg
    ln -s sheprd.svg $out/share/icons/hicolor/scalable/apps/herdr-gpui.svg
  '';

  postFixup = ''
    patchelf --add-rpath ${lib.makeLibraryPath finalAttrs.runtimeLibraries} $out/bin/sheprd
    wrapProgram $out/bin/sheprd \
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
    for program in sheprd sheprd-acp sheprd-remote-control sheprd-automate sheprd-nearby; do
      test -x "$out/bin/$program"
      # Capture before matching: with pipefail, grep -q exiting early
      # would fail the writer with SIGPIPE (as the release smoke notes).
      linked=$(ldd "$out/bin/$program" 2>/dev/null || true)
      if grep "not found" <<<"$linked"; then
        echo "$program has libraries the output does not carry" >&2
        exit 1
      fi
    done
    # The renamed commands keep working under the names installed configs use.
    for program in herdr-gpui herdr-acp herdr-remote-control herdr-automate herdr-nearby; do
      test -x "$out/bin/$program"
    done
    $out/bin/sheprd --help >/dev/null
    $out/bin/herdr-gpui --help >/dev/null
    $out/bin/sheprd-acp --help >/dev/null
    $out/bin/sheprd-remote-control --version >/dev/null
    $out/bin/sheprd-automate --version >/dev/null
    test "$($out/bin/sheprd-nearby --version)" = "sheprd-nearby ${finalAttrs.env.HERDR_RELEASE_VERSION}"
    $out/bin/herdr-automate --version >/dev/null
    $acp/bin/sheprd-acp --help >/dev/null
    $acp/bin/herdr-acp --help >/dev/null
    $remoteControl/bin/sheprd-remote-control --version >/dev/null
    $remoteControl/bin/herdr-remote-control --version >/dev/null
    $remoteControl/bin/herdr-acp --help >/dev/null
    test "$($automate/bin/sheprd-automate --version)" = "sheprd-automate ${finalAttrs.env.HERDR_RELEASE_VERSION}"
    $automate/bin/herdr-automate --version >/dev/null
    for standalone in "$acp" "$remoteControl" "$automate"; do
      test ! -e "$standalone/bin/sheprd"
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
    description = "Native GPUI client for an existing local Herdr daemon (Sheprd, renamed from herdr-gpui)";
    homepage = "https://herdrui.dev";
    changelog = "https://github.com/smdex/herdr-gpui/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "sheprd";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
