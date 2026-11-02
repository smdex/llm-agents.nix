{
  lib,
  stdenv,
  python3,
  fetchPypi,
  fetchurl,
  fetchFromGitHub,
  callPackage,
  rustPlatform,
  cargo,
  rustc,
  maturin,
  formatelf,
  versionCheckHook,
  versionCheckHomeHook,
  mkUpdater,
}:

let
  versionData = builtins.fromJSON (builtins.readFile ./hashes.json);
  inherit (versionData) version hashes;

  wheelPlatforms = {
    x86_64-linux = "manylinux_2_28_x86_64";
    aarch64-linux = "manylinux_2_28_aarch64";
    aarch64-darwin = "macosx_11_0_arm64";
  };

  wheelUrl = "https://files.pythonhosted.org/packages/cp312/m/mistral_vibe/mistral_vibe-{version}-cp312-abi3-{platform}.whl";

  textual-speedups = python3.pkgs.buildPythonPackage rec {
    pname = "textual-speedups";
    version = "0.2.1";
    pyproject = true;

    src = fetchPypi {
      pname = "textual_speedups";
      inherit version;
      hash = "sha256-cs8Pe97t4BU2e1m3C89yS6LDCAqGQevF65SzatFTaCQ=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit src;
      name = "${pname}-${version}";
      hash = "sha256-Bz4ocEziOlOX4z5F9EDry99YofeGyxL/6OTIf/WEgK4=";
    };

    nativeBuildInputs = [
      rustPlatform.cargoSetupHook
      rustPlatform.maturinBuildHook
      cargo
      rustc
      maturin
    ];

    pythonImportsCheck = [ "textual_speedups" ];

    meta = with lib; {
      description = "Optional Rust speedups for Textual TUI framework";
      homepage = "https://github.com/willmcgugan/textual-speedups";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  tree-sitter-bash = python3.pkgs.buildPythonPackage rec {
    pname = "tree-sitter-bash";
    version = "0.25.1";
    pyproject = true;

    src = fetchPypi {
      pname = "tree_sitter_bash";
      inherit version;
      hash = "sha256-v8C9qne8HobjxmUuWm4UDEDAoWuEGFwrY6182Am4jxQ=";
    };

    build-system = with python3.pkgs; [
      setuptools
    ];

    pythonImportsCheck = [ "tree_sitter_bash" ];

    meta = with lib; {
      description = "Bash grammar for tree-sitter";
      homepage = "https://github.com/tree-sitter/tree-sitter-bash";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.all;
    };
  };

  python = python3.override {
    self = python;
    packageOverrides = pyfinal: pyprev: {
      inherit textual-speedups tree-sitter-bash;

      # Upstream pins these with `==` and nixpkgs ships newer releases; keep
      # the tested versions until vibe moves to them.
      mistralai = callPackage ./mistralai.nix { python3 = python; };
      agent-client-protocol = callPackage ./agent-client-protocol.nix { python3 = python; };

      # vibe unpacks the 3-tuple yielded by mcp 1.x streamable_http_client;
      # mcp 2.x yields 2 values and breaks every connector/HTTP MCP call.
      mcp = pyprev.mcp_1;
      # The separate wire-types distribution needs the MCP 2 source layout.
      mcp-types = pyprev.mcp-types.override { mcp = pyprev.mcp; };

      # Vibe 3.0.4 needs the 1.45 family and its two new exporter distributions.
      opentelemetry-api = pyprev.opentelemetry-api.overridePythonAttrs {
        version = "1.45.1";
        src = fetchFromGitHub {
          owner = "open-telemetry";
          repo = "opentelemetry-python";
          tag = "v1.45.1";
          hash = "sha256-/WP+0J5Bd/XBpT69YsZaoSfARZwc2pAMVT3KeIjap40=";
        };
      };
      opentelemetry-semantic-conventions = pyprev.opentelemetry-semantic-conventions.overridePythonAttrs {
        version = "0.66b1";
      };
      opentelemetry-test-utils = pyprev.opentelemetry-test-utils.overridePythonAttrs {
        version = "0.66b1";
      };
      opentelemetry-exporter-http-transport =
        pyprev.opentelemetry-exporter-otlp-proto-common.overridePythonAttrs
          (old: {
            pname = "opentelemetry-exporter-http-transport";
            version = "0.66b1";
            sourceRoot = "${pyfinal.opentelemetry-api.src.name}/exporter/opentelemetry-exporter-http-transport";
            dependencies = with pyfinal; [
              opentelemetry-api
              requests
              urllib3
            ];
            nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pyfinal.mocket ];
            pythonImportsCheck = [ "opentelemetry.exporter.http.transport" ];
          });
      opentelemetry-exporter-otlp-common =
        pyprev.opentelemetry-exporter-otlp-proto-common.overridePythonAttrs
          {
            pname = "opentelemetry-exporter-otlp-common";
            version = "0.66b1";
            sourceRoot = "${pyfinal.opentelemetry-api.src.name}/exporter/opentelemetry-exporter-otlp-common";
            dependencies = with pyfinal; [
              opentelemetry-sdk
              opentelemetry-exporter-http-transport
            ];
            pythonImportsCheck = [ "opentelemetry.exporter.otlp.common" ];
          };

      # 1.40.0 added timing-sensitive tests that flake on loaded builders.
      opentelemetry-exporter-otlp-proto-http =
        pyprev.opentelemetry-exporter-otlp-proto-http.overridePythonAttrs
          (old: {
            nativeCheckInputs = (old.nativeCheckInputs or [ ]) ++ [ pyfinal.mocket ];
            dependencies = old.dependencies ++ [
              pyfinal.opentelemetry-exporter-http-transport
              pyfinal.opentelemetry-exporter-otlp-common
            ];
            disabledTests = (old.disabledTests or [ ]) ++ [
              "test_retry_timeout"
              "test_shutdown_interrupts_retry_backoff"
            ];
          });
    };
  };

in
python.pkgs.buildPythonApplication {
  pname = "mistral-vibe";
  inherit version;
  format = "wheel";

  src = fetchurl {
    url =
      builtins.replaceStrings
        [ "{version}" "{platform}" ]
        [
          version
          wheelPlatforms.${stdenv.hostPlatform.system}
        ]
        wheelUrl;
    hash = hashes.${stdenv.hostPlatform.system};
  };

  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ formatelf ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ stdenv.cc.cc.lib ];

  dependencies = with python.pkgs; [
    agent-client-protocol
    authlib
    anyio
    cachetools
    croniter
    cryptography
    gitpython
    giturlparse
    google-auth
    httpcore2
    httpx
    httpx2
    httpx-sse
    humanize
    jsonpatch
    joserfc
    keyring
    markdownify
    mcp
    mcp-types
    miniaudio
    mistralai
    opentelemetry-api
    opentelemetry-exporter-http-transport
    opentelemetry-exporter-otlp-common
    opentelemetry-exporter-otlp-proto-http
    opentelemetry-sdk
    opentelemetry-semantic-conventions
    packaging
    pexpect
    pydantic
    pydantic-settings
    pyperclip
    python-dotenv
    pyyaml
    requests
    rfc8785
    rich
    sentry-sdk
    setproctitle
    sounddevice
    socksio
    textual
    textual-speedups
    tomli-w
    tree-sitter
    tree-sitter-bash
    truststore
    uuid-utils
    watchfiles
    websockets
    zstandard
  ];

  # Upstream pins the whole dependency closure with `==`; nixpkgs versions
  # are newer but compatible.
  pythonRelaxDeps = true;

  # `import vibe` alone is lazy and misses dependency drift: mistralai 2.1.3
  # lacked mistralai.extra.observability.telemetry yet built fine and crashed
  # at runtime (issue #6462). Import submodules that pull in the vendored deps
  # so drift fails the build.
  pythonImportsCheck = [
    "vibe"
    "vibe.acp.entrypoint"
    "vibe.app_server.stdio"
    "vibe.app_server.local"
    "vibe.core.llm.completion"
    "vibe.cli.transcribe.mistral_transcribe_client"
  ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru = {
    category = "AI Coding Agents";
    tests.opentelemetry-sdk = python.pkgs.opentelemetry-sdk.overridePythonAttrs (old: {
      doCheck = true;
      # Preserve nixpkgs' performance-benchmark exclusion at its new upstream path.
      disabledTestPaths = (lib.remove "tests/performance/benchmarks/" (old.disabledTestPaths or [ ])) ++ [
        "benchmarks/"
      ];
    });
    updater = mkUpdater {
      kind = "platform";
      versionSource = {
        type = "json";
        url = "https://pypi.org/pypi/mistral-vibe/json";
        pointer = "/info/version";
      };
      urlTemplate = wheelUrl;
      platforms = wheelPlatforms;
    };
  };

  meta = with lib; {
    description = "Minimal CLI coding agent by Mistral AI - open-source command-line coding assistant powered by Devstral";
    homepage = "https://github.com/mistralai/mistral-vibe";
    changelog = "https://github.com/mistralai/mistral-vibe/releases/tag/v${version}";
    license = licenses.asl20;
    sourceProvenance = with sourceTypes; [
      fromSource
      binaryNativeCode
    ];
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "vibe";
  };
}
