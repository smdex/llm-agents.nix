{
  lib,
  flake,
  stdenv,
  fetchFromGitHub,
  makeWrapper,
  python3,
}:

let
  python = python3.withPackages (
    ps: with ps; [
      cryptography
      pyyaml
    ]
  );
in
stdenv.mkDerivation rec {
  pname = "hermes-webui";
  version = "0.51.599";

  src = fetchFromGitHub {
    owner = "nesquena";
    repo = "hermes-webui";
    rev = "v${version}";
    hash = "sha256-ZkzuePmZoPvKQTxXZrghwYYwQDOB6BVHOsNUVz6hryE=";
  };

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/hermes-webui $out/bin
    cp -R . $out/share/hermes-webui

    makeWrapper ${python}/bin/python $out/bin/hermes-webui \
      --chdir $out/share/hermes-webui \
      --set PYTHONPATH $out/share/hermes-webui \
      --add-flags $out/share/hermes-webui/server.py

    runHook postInstall
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Browser-based control panel for Hermes Agent";
    homepage = "https://github.com/nesquena/hermes-webui";
    changelog = "https://github.com/nesquena/hermes-webui/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = platforms.unix;
    mainProgram = "hermes-webui";
  };
}
