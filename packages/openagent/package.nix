{
  lib,
  flake,
  buildGoModule,
  fetchFromGitHub,
  versionCheckHook,
  versionCheckHomeHook,
}:

buildGoModule rec {
  pname = "openagent";
  version = "2.92.0";

  src = fetchFromGitHub {
    owner = "the-open-agent";
    repo = "openagent";
    tag = "v${version}";
    hash = "sha256-oV9Et1DphS8eymBM/umanJAkQasI3EkeYMGVEZmQV8E=";
  };

  vendorHash = "sha256-SEjo3GMRJMnx9RnTcSuRAegseo0fKgQsfl7SXnUMO34=";

  # Pure-Go build (modernc.org/sqlite, goleveldb) — no native deps.
  env.CGO_ENABLED = 0;

  ldflags = [
    "-s"
    "-w"
    "-X"
    "github.com/the-open-agent/openagent/internal/cli.Version=v${version}"
  ];

  # Large server with network/fixture-dependent tests.
  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = "--version";

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Personal AI assistant with RAG, agent loops, computer/browser-use and coding agent";
    homepage = "https://www.openagentai.org/";
    changelog = "https://github.com/the-open-agent/openagent/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "openagent";
    platforms = platforms.unix;
  };
}
