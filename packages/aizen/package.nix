{
  lib,
  flake,
  rustPlatform,
  fetchFromGitHub,
  git,
  bash,
  makeWrapper,
  versionCheckHook,
  versionCheckHomeHook,
}:

rustPlatform.buildRustPackage rec {
  pname = "aizen";
  version = "0.7.3";

  src = fetchFromGitHub {
    owner = "talmetis-labs";
    repo = "aizen";
    tag = "v${version}";
    hash = "sha256-2c/n7dKBvs/7URi8+JO9Kn3FyPyOyrnodUdTH5Yopow=";
  };

  cargoHash = "sha256-/ldPpC8P94F+LhiUVUg+LSpvROPgBPIke8PiryZK3ic=";

  # Upstream seeds prompt obfuscation from the build clock; keep builds reproducible.
  postPatch = ''
    substituteInPlace build.rs \
      --replace-fail 'use std::time::{SystemTime, UNIX_EPOCH};' 'use std::time::UNIX_EPOCH;' \
      --replace-fail 'SystemTime::now()' 'UNIX_EPOCH'
  '';

  nativeBuildInputs = [ makeWrapper ];

  # Unit tests assume FHS paths such as /bin/cat; exercise a hermetic CLI workflow instead.
  cargoTestFlags = [
    "--test"
    "resume_plan"
  ];

  postInstall = ''
    wrapProgram $out/bin/aizen --prefix PATH : ${
      lib.makeBinPath [
        git
        bash
      ]
    }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];

  passthru.category = "AI Coding Agents";

  meta = with lib; {
    description = "AI coding agent with a terminal interface and remote control";
    homepage = "https://github.com/talmetis-labs/aizen";
    changelog = "https://github.com/talmetis-labs/aizen/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "aizen";
    platforms = platforms.unix;
  };
}
