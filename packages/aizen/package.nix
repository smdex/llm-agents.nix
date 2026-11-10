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
  version = "0.7.4";

  src = fetchFromGitHub {
    owner = "talmetis-labs";
    repo = "aizen";
    tag = "v${version}";
    hash = "sha256-dla9CcP1ycEQq22LtL9/RbLm4ySa3ihxijpgarf4BOs=";
  };

  cargoHash = "sha256-ovVBEkwsbDwcUJF5aeaVhpXznOuBy7K80Pfu+vIx75I=";

  # Upstream seeds prompt obfuscation from the build clock; keep builds reproducible.
  postPatch = ''
    substituteInPlace build.rs \
      --replace-fail 'use std::time::{SystemTime, UNIX_EPOCH};' 'use std::time::UNIX_EPOCH;' \
      --replace-fail 'SystemTime::now()' 'UNIX_EPOCH'
    # Toolchains and their dynamic libraries live in the store, not FHS roots.
    substituteInPlace src/sandbox/policy.rs \
      --replace-fail '"/dev", "/run", "/var",' '"/dev", "/run", "/var", "/nix/store",'
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

  # Nix forbids nested protected-child creation; check the fail-closed policy
  # without trying to launch another sandbox inside the builder.
  postInstallCheck = ''
    sandboxStatus=$("$out/bin/aizen" sandbox status)
    grep -F 'unattended guarded fallback: off (fail-closed)' <<< "$sandboxStatus"
  '';

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
