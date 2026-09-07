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
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "alvinunreal";
    repo = "lazyskills";
    tag = "v${version}";
    hash = "sha256-uTosunMSnmgV0gr7eYhxbFAPYQu77Ou4Na8wtVEoiP0=";
  };

  vendorHash = "sha256-JBia588EtY89+vVGUiOyGwLD+rDqBwa2s/jjtd55DE0=";

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
