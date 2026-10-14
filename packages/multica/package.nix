{
  lib,
  flake,
  buildGo127Module,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGo127Module (finalAttrs: {
  pname = "multica";
  version = "0.6.2";

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    tag = "v${finalAttrs.version}";
    hash = "sha256-MVu93cGe+g1S835042cDwcTqC/5kwIR6myR9DwewDwU=";
  };

  sourceRoot = "${finalAttrs.src.name}/server";
  subPackages = [ "cmd/multica" ];

  vendorHash = "sha256-KJIrY4kLAQ5CBu/ClcXjLHG0FWvSX1ne06OG+ZkL75E=";

  ldflags = [ "-X main.version=${finalAttrs.version}" ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Command-line interface for the Multica platform";
    homepage = "https://github.com/multica-ai/multica";
    changelog = "https://github.com/multica-ai/multica/releases/tag/v${finalAttrs.version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "multica";
    platforms = lib.platforms.unix;
  };
})
