{
  lib,
  flake,
  buildGo127Module,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGo127Module (finalAttrs: {
  pname = "multica";
  version = "0.4.8-unstable-2026-10-08";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "multica";
    rev = "21216761afcdba769e3b99a87e31dc142c0f9165";
    hash = "sha256-FeRn/RgZPT520HINu2mM3hcpuaJ/Jc7iPumDzcUan0k=";
  };

  sourceRoot = "${finalAttrs.src.name}/server";
  subPackages = [ "cmd/multica" ];

  vendorHash = "sha256-b6elV4j+7R6L29q8tbCI3MAOY8X63ndzlmCMv7jo7mM=";

  ldflags = [ "-X main.version=${finalAttrs.version}" ];

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "AI Assistants";

  meta = {
    description = "Command-line interface for the Multica platform";
    homepage = "https://github.com/smdex/multica";
    changelog = "https://github.com/smdex/multica/commits/${finalAttrs.src.rev}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "multica";
    platforms = lib.platforms.unix;
  };
})
