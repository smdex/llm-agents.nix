{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
}:

buildGoModule (finalAttrs: {
  pname = "multica";
  version = "0-unstable-2026-10-07";

  src = fetchFromGitHub {
    owner = "smdex";
    repo = "multica";
    rev = "2c749ddf9f21421862523c3dbb10a843481e0378";
    hash = "sha256-/BoI2b2lBJtn0XsgSD0uqNLtcjRY0uBTPjudLZfNAoc=";
  };

  sourceRoot = "${finalAttrs.src.name}/server";
  subPackages = [ "cmd/multica" ];

  vendorHash = "sha256-SL//NLuzLV+faAjD7SR9f9j0AaDHel2haZajLJpsj5s=";

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
