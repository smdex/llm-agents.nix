{
  lib,
  flake,
  fetchFromGitHub,
  python3,
  makeWrapper,
  versionCheckHomeHook,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "cowagent";
  version = "2.1.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "zhayujie";
    repo = "CowAgent";
    tag = version;
    hash = "sha256-VnylwsIu6n/7Tkfys8djfqgVISqTkz3aCeyf0mYBGuk=";
  };

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'version = "1.0.0"' 'version = "${version}"'
    printf '%s\n' '${version}' > cli/VERSION
  '';

  build-system = with python3.pkgs; [
    setuptools
    wheel
  ];

  nativeBuildInputs = [ makeWrapper ];

  dependencies = with python3.pkgs; [
    click
    requests
  ];

  pythonImportsCheck = [ "cli" ];

  postInstall = ''
    mkdir -p $out/share/cowagent
    cp -r agent app.py bridge channel common config-template.json config.py models plugins skills translate voice $out/share/cowagent/

    sitePackages=$out/${python3.sitePackages}
    cp cli/VERSION "$sitePackages/cli/VERSION"
    substituteInPlace "$sitePackages/cli/utils.py" \
      --replace-fail 'return os.path.dirname(os.path.dirname(os.path.abspath(__file__)))' 'return os.environ.get("COWAGENT_ROOT", "'$out'/share/cowagent")'
    wrapProgram $out/bin/cow \
      --set-default COWAGENT_ROOT $out/share/cowagent
  '';

  doCheck = false;

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHomeHook ];
  installCheckPhase = ''
    runHook preInstallCheck
    cow version | grep -F "${version}"
    test -f $out/share/cowagent/app.py
    cow start --help >/dev/null
    runHook postInstallCheck
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "AI agent platform with a command-line interface";
    homepage = "https://github.com/zhayujie/CowAgent";
    changelog = "https://github.com/zhayujie/CowAgent/releases/tag/${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = platforms.unix;
    mainProgram = "cow";
  };
}
