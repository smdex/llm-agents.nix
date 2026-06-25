{
  lib,
  flake,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "mnemosyne-memory";
  version = "3.10.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "AxDSan";
    repo = "mnemosyne";
    tag = "v${version}";
    hash = "sha256-hpNnKc8ZNbqcy9X4Yu/4zMGEW7TCyT9aEfRv03ffuig=";
  };

  build-system = with python3.pkgs; [
    setuptools
    wheel
  ];

  dependencies = with python3.pkgs; [
    anyio
    cryptography
    fastembed
    mcp
    sqlite-vec
  ];

  pythonImportsCheck = [ "mnemosyne" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne --help >/dev/null
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne stats >/dev/null
    runHook postInstallCheck
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Universal Hermes-first SQLite memory layer for AI agents with MCP, sync, and vector search support";
    homepage = "https://github.com/AxDSan/mnemosyne";
    changelog = "https://github.com/AxDSan/mnemosyne/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "mnemosyne";
    platforms = platforms.all;
  };
}
