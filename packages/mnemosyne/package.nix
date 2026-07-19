{
  anyio,
  buildPythonPackage,
  callPackage,
  cryptography,
  fastapi,
  fastembed,
  fetchFromGitHub,
  flake,
  huggingface-hub,
  lib,
  llama-cpp-python,
  mcp,
  numpy,
  openclaw ? null,
  pytest,
  setuptools,
  sqlite-vec,
  uvicorn,
  wheel,
  python,
  rustCave001,
  mnemosyne-hermes,

  wrapperArgs ? [ ],
  extraDeps ? [ ],

  withCompression ? true,
  withEmbeddings ? true,
  withLocalLlm ? false,
}:

buildPythonPackage (finalAttrs: {
  pname = "mnemosyne-memory";
  version = "3.14.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mnemosyne-oss";
    repo = "mnemosyne";
    tag = "v${finalAttrs.version}";
    hash = "sha256-knAygCU7MdMsZMs92Jw1G8XcAAW/vS/I7UAMLm2112c=";
  };

  build-system = [
    setuptools
    wheel
  ];
  dependencies = [
    cryptography
    mcp
    anyio
    rustCave001
    numpy
    huggingface-hub
  ]
  ++ (lib.optionals withCompression [rustCave001])
  ++ (lib.optionals withEmbeddings finalAttrs.passthru.optional-dependencies.embeddings)
  ++ (lib.optionals withLocalLlm finalAttrs.passthru.optional-dependencies.llm)
  ++ extraDeps;
  optional-dependencies = {
    llm = [
      llama-cpp-python
      huggingface-hub
      # ctransformers2
    ];
    embeddings = [
      fastembed
      sqlite-vec
    ];
    openclaw = lib.optional (openclaw != null) openclaw;
    all = [
      llama-cpp-python
      huggingface-hub
      fastembed
      sqlite-vec
      mcp
      anyio
    ];
  };
  pythonPath = [
    fastapi
    uvicorn
  ];
  nativeCheckInputs = [ pytest ];

  # Keep user-level Python overlays from contaminating the packaged CLI. Sergio's
  # Hermes profile may export PYTHONPATH for Hermes itself; mixing that py312
  # tree into this py313 application breaks imports such as pydantic-core.
  makeWrapperArgs = [
    "--unset"
    "PYTHONPATH"
  ] ++ wrapperArgs;

  pythonImportsCheck = [
    "mnemosyne"
  ]
  ++ lib.optionals withCompression [ "rust_cave_001" ]
  ++ lib.optionals withEmbeddings [ "fastembed" ]
  ++ lib.optionals withLocalLlm [ "huggingface_hub" "numpy" ];

  postInstall = ''
    rm -rf $out/${python.sitePackages}/examples
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne --help
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne stats
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne python - <<'PY'
    from mnemosyne.integrations.memory_browser import create_app

    app = create_app(banks=["default"], default_bank="default")
    assert app.title == "Mnemosyne Browser"
    PY
    ${lib.optionalString withCompression ''
      python - <<'PY'
      from mnemosyne.core.plugins import CompressionPlugin
      import rust_cave_001

      plugin = CompressionPlugin({"enabled": True, "threshold_chars": 10})
      compressed = plugin.compress_lines([
          "The database needs an index because the queries are too slow and the users are waiting."
      ])
      assert len(compressed) == 1
      assert isinstance(compressed[0], str)
      assert compressed[0]
      PY
    ''}
    HERMES_HOME=$TMPDIR/hermes $out/bin/mnemosyne-install
    runHook postInstallCheck
  '';

  passthru = {
    category = "AI Assistants";
    inherit rustCave001 mnemosyne-hermes;
    optionalRuntimeDependencies = {
      compression = withCompression;
      embeddings = withEmbeddings;
      localLlm = withLocalLlm;
    };
    hermesPlugin = callPackage ./hermes-plugin.nix {
      mnemosyne = finalAttrs.finalPackage;
    };
  };

  meta = with lib; {
    description = "Universal Hermes-first SQLite memory layer for AI agents with MCP, sync, and vector search support";
    homepage = "https://github.com/mnemosyne-oss/mnemosyne";
    changelog = "https://github.com/mnemosyne-oss/mnemosyne/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "mnemosyne";
    platforms = platforms.all;
  };
})
