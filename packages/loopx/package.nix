{
  lib,
  python3,
  fetchFromGitHub,
  versionCheckHook,
  versionCheckHomeHook,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "loopx";
  version = "0.4.5";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "huangruiteng";
    repo = "loopx";
    tag = "v${version}";
    hash = "sha256-xF8L4dqEtXTgqSgfzhJyVLAO5pJxlJkRM604DP8bp6Y=";
  };

  build-system = with python3.pkgs; [
    setuptools
  ];

  dependencies = [ ];

  pythonImportsCheck = [ "loopx" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Lightweight Loop Engineering control plane for long-running agent goals";
    homepage = "https://github.com/huangruiteng/loopx";
    changelog = "https://github.com/huangruiteng/loopx/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    mainProgram = "loopx";
    platforms = platforms.all;
  };
}
