{
  lib,
  flake,
  fetchFromGitHub,
  stdenv,
  nodejs,
  bash,
  git,
  makeShellWrapper,
  # The kit ships a vc-agent-browser skill built on puppeteer+sharp. Rather than
  # vendor those native node deps, the optional browser backend reuses this
  # flake's self-contained `agent-browser` package (vercel-labs, Rust + bundled
  # Chromium). It is only pulled into the closure when enabled:
  #   vibecode-pro-max-kit.override { withAgentBrowser = true; }
  withAgentBrowser ? false,
  agent-browser,
}:

assert lib.versionAtLeast nodejs.version "22"; # fs.globSync in resolver needs Node >= 22

stdenv.mkDerivation rec {
  pname = "vibecode-pro-max-kit";
  version = "3.2.5";

  src = fetchFromGitHub {
    owner = "withkynam";
    repo = "vibecode-pro-max-kit";
    tag = "v${version}";
    hash = "sha256-12FKd0idv4k0taFnQffSAabokMuMMaomhL5+HUtPHkk=";
  };

  nativeBuildInputs = [ makeShellWrapper ];
  buildInputs = [
    nodejs
    bash
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild
    # Rewrite every shebang so the kit's scripts and hooks run on NixOS, which
    # has no /usr/bin/env. Only line 1 is touched, so non-shebang files are
    # left untouched.
    find . -type f \( -name '*.mjs' -o -name '*.js' -o -name '*.cjs' -o -name '*.sh' \) \
      -exec sed -i \
        -e "1s|#!/usr/bin/env node|#!${nodejs}/bin/node|" \
        -e "1s|#!/usr/bin/env bash|#!${bash}/bin/bash|" \
        -e "1s|#!/bin/bash|#!${bash}/bin/bash|" \
        -e "1s|#!/bin/sh|#!${bash}/bin/sh|" \
      {} +
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    share=$out/share/vibecode-pro-max-kit
    mkdir -p "$share"
    # Install the whole kit (agents, skills, hooks, protocols, installer) with
    # shebangs already patched. -a preserves the .agents → .claude/skills symlink.
    cp -a . "$share/"

    # The single user-facing command: install the kit into the current project,
    # sourcing it from the nix store instead of curl|bash from GitHub. install.sh
    # honours VC_KIT_SOURCE for a local source dir (copies instead of cloning).
    mkdir -p "$out/bin"
    makeShellWrapper ${bash}/bin/bash "$out/bin/vibecode-pro-max-kit-install" \
      --set-default VC_KIT_SOURCE "$share" \
      --prefix PATH : ${
        lib.makeBinPath (
          [
            nodejs
            bash
            git
          ]
          ++ lib.optional withAgentBrowser agent-browser
        )
      } \
      --add-flags "$share/install.sh"

    ${
      if withAgentBrowser then
        ''
          # Expose the flake's self-contained browser-automation CLI alongside the
          # kit so the vc-agent-browser skill has a working native backend.
          ln -s ${agent-browser}/bin/agent-browser "$out/bin/agent-browser"
        ''
      else
        ""
    }
    runHook postInstall
  '';

  passthru.category = "Workflow & Project Management";

  meta = with lib; {
    description = "Spec-driven coding harness kit (agents, skills, hooks) for Claude Code and Codex";
    homepage = "https://github.com/withkynam/vibecode-pro-max-kit";
    changelog = "https://github.com/withkynam/vibecode-pro-max-kit/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "vibecode-pro-max-kit-install";
    platforms = platforms.unix;
  };
}
