{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  flake,
}:

let
  pythonEnv = python3.withPackages (ps: [
    ps.litellm
  ]);
in
stdenvNoCC.mkDerivation rec {
  pname = "adversarial-spec";
  version = "0-unstable-2026-01-22";

  src = fetchFromGitHub {
    owner = "zscole";
    repo = "adversarial-spec";
    rev = "f90cf0c36c3999b8dc272c9c06dee9846076f369";
    hash = "sha256-EhRdkk9iDy5QrqETx4Wan5rPs9ex9Degma/Q2ZedT1Y=";
  };

  nativeBuildInputs = [ makeWrapper ];

  postPatch = ''
    substituteInPlace skills/adversarial-spec/scripts/providers.py \
      --replace-fail 'GLOBAL_CONFIG_PATH = Path.home() / ".claude" / "adversarial-spec" / "config.json"' 'GLOBAL_CONFIG_PATH = Path(os.environ.get("ADVERSARIAL_SPEC_CONFIG", str(Path.home() / ".config" / "adversarial-spec" / "config.json")))' \
      --replace-fail 'Load global config from ~/.claude/adversarial-spec/config.json.' 'Load global config from ~/.config/adversarial-spec/config.json.' \
      --replace-fail 'Save global config to ~/.claude/adversarial-spec/config.json.' 'Save global config to ~/.config/adversarial-spec/config.json.' \
      --replace-quiet 'python3 debate.py' 'adversarial-spec'

    substituteInPlace skills/adversarial-spec/scripts/debate.py \
      --replace-quiet 'python3 debate.py' 'adversarial-spec'
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/libexec/adversarial-spec
    cp -r skills/adversarial-spec/scripts/* $out/libexec/adversarial-spec/

    makeWrapper ${pythonEnv}/bin/python $out/bin/adversarial-spec \
      --add-flags "$out/libexec/adversarial-spec/debate.py"
    makeWrapper ${pythonEnv}/bin/python $out/bin/adversarial-spec-telegram \
      --add-flags "$out/libexec/adversarial-spec/telegram_bot.py"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck

    $out/bin/adversarial-spec providers | grep -q "Supported providers"
    $out/bin/adversarial-spec focus-areas | grep -q "Available focus areas"
    $out/bin/adversarial-spec-telegram --help | grep -q "Telegram bot utilities"

    runHook postInstallCheck
  '';

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Multi-model adversarial debate for refining product and technical specifications";
    homepage = "https://github.com/zscole/adversarial-spec";
    changelog = "https://github.com/zscole/adversarial-spec/blob/${src.rev}/CHANGELOG.md";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "adversarial-spec";
    platforms = platforms.all;
  };
}
