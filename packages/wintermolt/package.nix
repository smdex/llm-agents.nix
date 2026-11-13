{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  zig_0_16,
  pkg-config,
  curl,
  sqlite,
  versionCheckHook,
  versionCheckHomeHook,
}:

stdenv.mkDerivation rec {
  pname = "wintermolt";
  version = "0.7.0";

  src = fetchFromGitHub {
    owner = "lupin4";
    repo = "wintermolt";
    tag = "v${version}";
    hash = "sha256-VZeKChfWrifRXUZUsJoekhFv/Lb5HeqVtUD57bHDtVM=";
  };

  nativeBuildInputs = [
    zig_0_16.hook
    pkg-config
  ];
  buildInputs = [
    curl
    sqlite
  ];

  zigBuildFlags = [ "-Doptimize=ReleaseSmall" ];
  doCheck = true;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  postInstallCheck = ''
    "$out/bin/wintermolt" --help > /dev/null
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Native AI assistant with multiple backends, MCP, and chat bridges";
    homepage = "https://github.com/lupin4/wintermolt";
    changelog = "https://github.com/lupin4/wintermolt/releases/tag/v${version}";
    license = licenses.asl20;
    # Upstream links its bundled llama.cpp archive on Apple Silicon.
    sourceProvenance = [
      sourceTypes.fromSource
    ]
    ++ optional stdenv.hostPlatform.isDarwin sourceTypes.binaryNativeCode;
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "wintermolt";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
