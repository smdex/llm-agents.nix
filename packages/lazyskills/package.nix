{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  versionCheckHook,
}:

buildGoModule.override { go = go_1_26; } rec {
  pname = "lazyskills";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "alvinunreal";
    repo = "lazyskills";
    tag = "v${version}";
    hash = "sha256-zIOUKi5bfVTukItudUcQ44Mgh2Pze+MM6d0W/pj+UdY=";
  };

  vendorHash = "sha256-P8bweTw1Htc3HFWPOJJNSIKlp62LWfKzK3MVAC98Svs=";

  subPackages = [ "cmd/lazyskills" ];

  ldflags = [
    "-s"
    "-w"
    "-X=main.version=${version}"
  ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Claude Code Ecosystem";

  meta = with lib; {
    description = "Mission control for agent skills";
    homepage = "https://lazyskills.sh";
    changelog = "https://github.com/alvinunreal/lazyskills/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "lazyskills";
    platforms = platforms.all;
  };
}
