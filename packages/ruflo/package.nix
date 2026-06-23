{
  lib,
  flake,
  fetchFromGitHub,
  fetchzip,
  buildNpmPackage,
  makeWrapper,
  nodejs,
  versionCheckHomeHook,
}:

let
  nativeDeps = {
    ruvector-attention-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/attention-linux-x64-gnu/-/attention-linux-x64-gnu-0.1.31.tgz";
      hash = "sha256-kskyJQm8fUdTP8TDJbsY5ILkyJJIWUFCf+leR98ph6c=";
    };
    ruvector-gnn-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/gnn-linux-x64-gnu/-/gnn-linux-x64-gnu-0.1.25.tgz";
      hash = "sha256-EJsjFD11A54aX4xG6K3VkECZ7IUooAzHb0bcPsPmjbk=";
    };
    ruvector-graph-node-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/graph-node-linux-x64-gnu/-/graph-node-linux-x64-gnu-2.0.2.tgz";
      hash = "sha256-Q561+itksszHw+ZC9Tv+rcplOBJU/oWzBwZCdnIV9sQ=";
    };
    ruvector-graph-transformer-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/graph-transformer-linux-x64-gnu/-/graph-transformer-linux-x64-gnu-2.0.4.tgz";
      hash = "sha256-3o7Qhqnby8UvuFmuiNvW1/Ad8gDXvbHPmrwQslfQL2I=";
    };
    ruvector-router-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/router-linux-x64-gnu/-/router-linux-x64-gnu-0.1.30.tgz";
      hash = "sha256-WDalH2ta21hpZuzsucXCaRNw6egmq4oHRHdSdI37doo=";
    };
    ruvector-ruvllm-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/ruvllm-linux-x64-gnu/-/ruvllm-linux-x64-gnu-2.0.1.tgz";
      hash = "sha256-AT1NazZAtd1By3BkmCk0FqdTjrRR8gr0jQGp1s7M4HM=";
    };
    ruvector-ruvllm-linux-x64-gnu-agentic-flow = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/ruvllm-linux-x64-gnu/-/ruvllm-linux-x64-gnu-0.2.0.tgz";
      hash = "sha256-cMpEr6kl0HLL8Br20fhUXSxyUALgJrOX7b7+PMgWTTQ=";
    };
    ruvector-rvf-node-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/rvf-node-linux-x64-gnu/-/rvf-node-linux-x64-gnu-0.1.7.tgz";
      hash = "sha256-g7BWuHjC4G7vK0BB0SLULykB0hfunNenqr80eNEb6CA=";
    };
    ruvector-sona-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/sona-linux-x64-gnu/-/sona-linux-x64-gnu-0.1.5.tgz";
      hash = "sha256-wYN62cgI3sRSkrcri2I+7NyETDklfRAQpFW4SYzXOh0=";
    };
    ruvector-tiny-dancer-linux-x64-gnu = fetchzip {
      url = "https://registry.npmjs.org/@ruvector/tiny-dancer-linux-x64-gnu/-/tiny-dancer-linux-x64-gnu-0.1.15.tgz";
      hash = "sha256-kYGot9AFo9hrW+yKUuEiNOMPkBo9q780E1yAzTyTai8=";
    };
  };
in
buildNpmPackage rec {
  npmDepsFetcherVersion = 2;
  pname = "ruflo";
  version = "3.14.1";

  src = fetchFromGitHub {
    owner = "ruvnet";
    repo = "ruflo";
    rev = "d065b15927c6ba7318623e8af123e7980e4c6681";
    hash = "sha256-/o38mscicdVjByc2nYifPfo6vIJmDg7C2Mf0jO2aBX8=";
  };

  npmDepsHash = "sha256-8KSdmbTAum3wsC074yhYplYskgwCdKEaZIzriXQylw8=";
  makeCacheWritable = true;

  nativeBuildInputs = [ makeWrapper ];

  npmFlags = [ "--ignore-scripts" ];

  npmBuildScript = "build:ts";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/ruflo $out/bin
    cp -r . $out/share/ruflo

    # Keep upstream's native @ruvector packages as separate Nix derivations
    # while preserving the node_modules paths expected at runtime.
    mkdir -p $out/share/ruflo/node_modules/@ruvector
    for pkg in \
      attention-linux-x64-gnu \
      gnn-linux-x64-gnu \
      graph-node-linux-x64-gnu \
      graph-transformer-linux-x64-gnu \
      router-linux-x64-gnu \
      ruvllm-linux-x64-gnu \
      rvf-node-linux-x64-gnu \
      sona-linux-x64-gnu \
      tiny-dancer-linux-x64-gnu
    do
      rm -rf "$out/share/ruflo/node_modules/@ruvector/$pkg"
    done
    ln -s ${nativeDeps.ruvector-attention-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/attention-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-gnn-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/gnn-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-graph-node-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/graph-node-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-graph-transformer-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/graph-transformer-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-router-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/router-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-ruvllm-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/ruvllm-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-rvf-node-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/rvf-node-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-sona-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/sona-linux-x64-gnu
    ln -s ${nativeDeps.ruvector-tiny-dancer-linux-x64-gnu} $out/share/ruflo/node_modules/@ruvector/tiny-dancer-linux-x64-gnu

    if [ -d $out/share/ruflo/node_modules/agentic-flow/node_modules/@ruvector ]; then
      rm -rf $out/share/ruflo/node_modules/agentic-flow/node_modules/@ruvector/ruvllm-linux-x64-gnu
      ln -s ${nativeDeps.ruvector-ruvllm-linux-x64-gnu-agentic-flow} $out/share/ruflo/node_modules/agentic-flow/node_modules/@ruvector/ruvllm-linux-x64-gnu
    fi

    makeWrapper ${lib.getExe nodejs} $out/bin/ruflo \
      --add-flags "$out/share/ruflo/ruflo/bin/ruflo.js" \
      --set NODE_PATH "$out/share/ruflo/node_modules"
    makeWrapper ${lib.getExe nodejs} $out/bin/claude-flow \
      --add-flags "$out/share/ruflo/ruflo/bin/ruflo.js" \
      --set NODE_PATH "$out/share/ruflo/node_modules"

    runHook postInstall
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHomeHook ];
  installCheckPhase = ''
    runHook preInstallCheck
    $out/bin/ruflo --version | grep -F "${version}"
    $out/bin/claude-flow --version >/dev/null
    runHook postInstallCheck
  '';

  passthru = {
    category = "AI Coding Agents";
    inherit nativeDeps;
  };

  meta = with lib; {
    description = "Agentic orchestration CLI with ruv-FANN neural capabilities";
    homepage = "https://github.com/ruvnet/ruflo";
    changelog = "https://github.com/ruvnet/ruflo/releases";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "ruflo";
  };
}
