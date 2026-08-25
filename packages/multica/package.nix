{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  go_1_26,
  unpinGoModVersionHook,
}:

# v0.4.30 pins go 1.26.6 in server/go.mod but nixpkgs go_1_26 is 1.26.5.
# Relax the go.mod constraint until nixpkgs reaches 1.26.6, then drop the hook.
(buildGoModule.override { go = go_1_26; }) rec {
  pname = "multica";
  version = "0.4.34";

  src = fetchFromGitHub {
    owner = "multica-ai";
    repo = "multica";
    tag = "v${version}";
    hash = "sha256-AZydORKAzxcmKcxFNdFHbJlQMTr+2Cj2uFJXitYoAeo=";
  };

  sourceRoot = "source/server";
  subPackages = [ "cmd/multica" ];

  nativeBuildInputs = [ unpinGoModVersionHook ];

  vendorHash = "sha256-QwVYfMtRL4eSRvQ9TuuVQyRXUHWPQXoAzdd9KX+D8lQ=";

  ldflags = [
    "-X main.version=${version}"
    "-X main.commit=d563bfbc0"
    "-X main.date=2026-08-19T10:03:12Z"
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
