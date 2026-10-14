{
  lib,
  flake,
  python3,
  stdenv,
  fetchPypi,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  data = lib.importJSON ./hashes.json;
  system = stdenv.hostPlatform.system;
  wheelPlatforms = {
    x86_64-linux = "manylinux_2_17_x86_64";
    aarch64-darwin = "macosx_11_0_arm64";
  };
in
python3.pkgs.buildPythonApplication rec {
  pname = "hol-guard";
  inherit (data) version;
  format = "wheel";
  dontStrip = true; # The bundled manifests verify the original runtime bytes.

  # Upstream no longer publishes source distributions. Its native wheels
  # bundle the required runtime and its integrity manifests; Linux is static.
  src = fetchPypi {
    pname = "hol_guard";
    inherit version;
    format = "wheel";
    dist = "py3";
    python = "py3";
    abi = "none";
    platform = wheelPlatforms.${system} or "any";
    hash = data.hashes.${system} or data.hashes.any;
  };

  dependencies = with python3.pkgs; [
    cryptography
    idna
    jsonschema
    keyring
    mcp
    packaging
    publicsuffixlist
    pyyaml
    regex
    requests
    rich
    tomlkit
    typing-extensions
  ];

  pythonRelaxDeps = true;

  pythonImportsCheck = [ "codex_plugin_scanner" ];

  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  postInstallCheck = ''
    PYTHONPATH="$out/${python3.sitePackages}:$PYTHONPATH" ${python3.interpreter} -c '
      from codex_plugin_scanner.guard.native_runtime import native_runtime_status
      status = native_runtime_status()
      assert status.available, status
    '
  '';

  passthru.category = "Utilities";

  meta = {
    description = "Open-source antivirus and runtime protection for AI agents";
    homepage = "https://hol.org/guard";
    changelog = "https://github.com/hashgraph-online/hol-guard/releases/tag/v${version}";
    license = lib.licenses.asl20;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    maintainers = with flake.lib.maintainers; [ kantorcodes ];
    mainProgram = "hol-guard";
    platforms = builtins.attrNames wheelPlatforms;
  };
}
