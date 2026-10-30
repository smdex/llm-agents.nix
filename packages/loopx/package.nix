{
  lib,
  python3,
  fetchPypi,
  versionCheckHook,
  versionCheckHomeHook,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "loopx";
  version = "2.1.1";
  pyproject = true;

  # PyPI distributions include the validated chat frontend required at build time.
  src = fetchPypi {
    inherit pname version;
    hash = "sha256-CYz+xVx50IqAyjJKeWd6nAv0xPUxAHl+wHq1mxl9BAQ=";
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
