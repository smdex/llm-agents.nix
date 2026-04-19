{
  lib,
  buildGoModule,
  fetchFromGitHub,
  go-bin,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule.override { go = go-bin; } rec {
  pname = "mardi-gras";
  version = "0.17.0";

  src = fetchFromGitHub {
    owner = "quietpublish";
    repo = "mardi-gras";
    rev = "v${version}";
    hash = "sha256-zBrUOVcuAOeVQsm3TdBREkJwJgd2BR/5pKXUROtDab0=";
  };

  vendorHash = "sha256-CbftluOGy00UtbStnH544kLAI63lC5rL3BZUp+Gf5Bc=";

  subPackages = [ "cmd/mg" ];

  ldflags = [
    "-s"
    "-w"
    "-X main.version=${version}"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Terminal UI for Beads issue tracking with a parade-inspired workflow view";
    homepage = "https://github.com/quietpublish/mardi-gras";
    changelog = "https://github.com/quietpublish/mardi-gras/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ zimbatm ];
    mainProgram = "mg";
    platforms = platforms.unix;
  };
}
