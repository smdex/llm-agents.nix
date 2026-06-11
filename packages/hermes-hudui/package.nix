{
  lib,
  flake,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "hermes-hudui";
  version = "0.9.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "joeynyc";
    repo = "hermes-hudui";
    rev = "v${version}";
    hash = "sha256-S/+ylp1KYeBRqazU/Uy3VX15n8zBrYkMJMzG65u8ka4=";
  };

  build-system = with python3.pkgs; [
    setuptools
    wheel
  ];

  dependencies = with python3.pkgs; [
    cryptography
    fastapi
    pillow
    pyyaml
    uvicorn
    watchfiles
  ];

  pythonImportsCheck = [ "backend.main" ];

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Web UI consciousness monitor for Hermes";
    homepage = "https://github.com/joeynyc/hermes-hudui";
    changelog = "https://github.com/joeynyc/hermes-hudui/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = platforms.unix;
    mainProgram = "hermes-hudui";
  };
}
