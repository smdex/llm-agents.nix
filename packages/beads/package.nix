{
  lib,
  buildGoModule,
  fetchFromGitHub,
  makeWrapper,
  dolt,
  unpinGoModVersionHook,
  versionCheckHook,
}:

buildGoModule rec {
  pname = "beads";
  version = "0.63.2";

  src = fetchFromGitHub {
    owner = "steveyegge";
    repo = "beads";
    rev = "v${version}";
    hash = "sha256-ERRw+SgRgFzY+cchRRsCYUtKCXvRZOdWJuSAQPDVF3M=";
  };

  vendorHash = "sha256-GYPfvsI8eNJbdzrbO7YnMkN2Yt6KZNB7w/2SJD2WdFY=";

  nativeBuildInputs = [
    unpinGoModVersionHook
    makeWrapper
  ];

  subPackages = [ "cmd/bd" ];

  doCheck = false;

  postInstall = ''
    wrapProgram $out/bin/bd \
      --prefix PATH : ${lib.makeBinPath [ dolt ]}
  '';

  doInstallCheck = true;

  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "A distributed issue tracker designed for AI-supervised coding workflows";
    homepage = "https://github.com/steveyegge/beads";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with maintainers; [ zimbatm ];
    mainProgram = "bd";
    platforms = platforms.unix;
  };
}
