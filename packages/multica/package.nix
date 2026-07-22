{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
}:

(buildGoModule.override { go = go_1_26; }) rec {
  pname = "multica";
  version = "0.4.8";

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    tag = "v${version}";
    hash = "sha256-Zd/duDSueDEcijQQXb15QneUJP+rC3ohs2ErsPpUVc0=";
  };

  sourceRoot = "source/server";
  subPackages = [ "cmd/multica" ];
  vendorHash = "sha256-SL//NLuzLV+faAjD7SR9f9j0AaDHel2haZajLJpsj5s=";

  ldflags = [
    "-X main.version=${version}"
    "-X main.commit=8ca30e794"
    "-X main.date=2026-07-17T10:04:06Z"
  ];

  doCheck = false;

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Command-line interface for the Multica platform";
    homepage = "https://github.com/multica-ai/multica";
    changelog = "https://github.com/multica-ai/multica/releases/tag/v${version}";
    license = flake.lib.licenses.unfree;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "multica";
    platforms = platforms.linux ++ platforms.darwin;
  };
}
