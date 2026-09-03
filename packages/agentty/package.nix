{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  pkg-config,
  openssl,
  nghttp2,
  nlohmann_json,
  simdjson,
  versionCheckHook,
  versionCheckHomeHook,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "agentty";
  version = "0.6.0";

  src = fetchFromGitHub {
    owner = "1ay1";
    repo = "agentty";
    tag = "v${finalAttrs.version}";
    hash = "sha256-QZCNy9080NkpdgSqni/VZo4VHjYI5FVY4Q400RCGdFo=";
    # maya / acp-cpp / mcp-cpp / rag-cpp are git submodules pinned by commit
    # in the tag's tree; materializing them here pins the whole tree with one
    # hash. The fetcher strips .git, which also disables agentty's
    # AGENTTY_AUTO_PULL_SUBMODULES (it no-ops when the parent isn't a checkout).
    fetchSubmodules = true;
  };

  nativeBuildInputs = [
    cmake
    ninja
    pkg-config # nghttp2 falls back to pkg_check_modules(libnghttp2)
  ];

  buildInputs = [
    openssl
    nghttp2
    nlohmann_json
    simdjson
  ];

  # FETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS turns the FetchContent fetches
  # for nlohmann_json / simdjson (declared by agentty and again by acp-cpp /
  # mcp-cpp / rag-cpp) into find_package calls, so the pinned nixpkgs
  # libraries satisfy them instead of a sandbox-violating git fetch. This
  # deliberately builds against nixpkgs' versions (simdjson 4.x compiles fine
  # against the 3.10.1-era ondemand API agentty uses) rather than vendoring.
  #
  # mimalloc is routed through FetchContent too; disabled in favour of the
  # system allocator rather than vendoring another copy of it.
  #
  # MAYA_NATIVE_TUNING=OFF: maya defaults to -march=native, which would bake
  # the build host's microarchitecture into the output. Upstream only turns
  # it off itself under AGENTTY_STANDALONE.
  cmakeFlags = [
    (lib.cmakeFeature "CMAKE_BUILD_TYPE" "Release")
    (lib.cmakeFeature "FETCHCONTENT_TRY_FIND_PACKAGE_MODE" "ALWAYS")
    (lib.cmakeBool "AGENTTY_USE_MIMALLOC" false)
    (lib.cmakeBool "MAYA_NATIVE_TUNING" false)
    (lib.cmakeBool "AGENTTY_BUILD_TESTS" false)
  ];

  # Upstream's CMakeLists has no install() rules; the binary is a plain
  # build-dir artifact.
  installPhase = ''
    runHook preInstall
    install -Dm755 agentty $out/bin/agentty
    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = {
    description = "AI pair programming in your terminal — a C++26 Claude Code alternative with sub-millisecond startup";
    homepage = "https://github.com/1ay1/agentty";
    changelog = "https://github.com/1ay1/agentty/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    # Matches the platforms upstream ships release binaries for. The tree also
    # has macOS support, but it needs a clang advertising cxx_std_23 and is
    # untested here; add darwin platforms after a native build passes.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "agentty";
  };
})
