{
  lib,
  flake,
  python3,
  fetchFromGitHub,
  rustPlatform,
  cargo,
  rustc,
  enableCompression ? true,
  enableFastembed ? true,
  enableSqliteVec ? true,
  enableNumpy ? true,
  enableHuggingfaceHub ? true,
}:

let
  rustCave001 = python3.pkgs.buildPythonPackage rec {
    pname = "rust-cave-001";
    version = "0.4.3";
    pyproject = true;

    src = fetchFromGitHub {
      owner = "ether-btc";
      repo = "rust-cave-001";
      tag = "v${version}";
      hash = "sha256-QPBPzeBaa32oMGTrMbNNthxAxkXvDk1Ljc32znOawB8=";
    };

    cargoDeps = rustPlatform.fetchCargoVendor {
      inherit pname version src;
      hash = "sha256-WHgzZEZE4tD8MXAi5UDC739WNiq+J3wq+aA2FSrHUYA=";
    };

    build-system = [
      cargo
      rustPlatform.cargoSetupHook
      rustPlatform.maturinBuildHook
      rustc
    ];

    doCheck = false;
    pythonImportsCheck = [ "rust_cave_001" ];

    meta = with lib; {
      description = "Rust-backed Python bindings for Caveman text compression";
      homepage = "https://github.com/ether-btc/rust-cave-001";
      changelog = "https://github.com/ether-btc/rust-cave-001/releases/tag/v${version}";
      license = licenses.mit;
      sourceProvenance = with sourceTypes; [ fromSource ];
      maintainers = with flake.lib.maintainers; [ smdex ];
      platforms = platforms.all;
    };
  };

  optionalRuntimeDeps =
    with python3.pkgs;
    lib.optionals enableCompression [ rustCave001 ]
    ++ lib.optionals enableFastembed [ fastembed ]
    ++ lib.optionals enableSqliteVec [ sqlite-vec ]
    ++ lib.optionals enableNumpy [ numpy ]
    ++ lib.optionals enableHuggingfaceHub [ huggingface-hub ];
in
python3.pkgs.buildPythonApplication rec {
  pname = "mnemosyne-memory";
  version = "3.12.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mnemosyne-oss";
    repo = "mnemosyne";
    tag = "v${version}";
    hash = "sha256-SczjGMESWXw6AvPlgWfSZwSTGZ82zQSzuSvBcimwo9M=";
  };

  postPatch = ''
        # The entry point calls install() directly, so upstream argparse is bypassed
        # for mnemosyne-install. Handle command-line flags before it mutates a
        # user's Hermes configuration.
        substituteInPlace mnemosyne/install.py \
          --replace-fail 'def install():
        """Run the full Mnemosyne Hermes installation."""
        print("🌀 Mnemosyne Hermes Installer")
    ' 'def install():
        """Run the full Mnemosyne Hermes installation."""
        if any(arg in ("-h", "--help") for arg in sys.argv[1:]):
            print("Usage: mnemosyne-install [--help] [--uninstall]")
            return
        if "--uninstall" in sys.argv[1:]:
            uninstall()
            return
        unknown = [arg for arg in sys.argv[1:] if arg != "--uninstall"]
        if unknown:
            print(f"Unknown option: {unknown[0]}", file=sys.stderr)
            sys.exit(2)

        print("🌀 Mnemosyne Hermes Installer")
    '

        # Upstream 3.12.2 renders PAGE_HTML through str.format(), so CSS blocks
        # such as "{ --bg: ... }" are parsed as replacement fields and the index
        # route raises KeyError. Replace only the declared template markers.
            python -c '
        from pathlib import Path
        path = Path("mnemosyne/integrations/memory_browser.py")
        source = path.read_text()
        start = source.index("    return PAGE_HTML.format(")
        end = source.index("\n\n\n# ── FastAPI App", start)
        replacement = """    return (
                PAGE_HTML
                .replace("{query}", query)
                .replace("{source_options}", source_opts)
                .replace("{sel_working}", "selected" if tier == "working" else "")
                .replace("{sel_episodic}", "selected" if tier == "episodic" else "")
                .replace("{sel_recent}", "selected" if sort == "recent" else "")
                .replace("{sel_importance}", "selected" if sort == "importance" else "")
                .replace("{results_html}", results)
            )"""
        path.write_text(source[:start] + replacement + source[end:])
        '
  '';

  build-system = with python3.pkgs; [
    setuptools
    wheel
  ];

  dependencies =
    with python3.pkgs;
    [
      anyio
      cryptography
      fastapi
      mcp
      uvicorn
    ]
    ++ optionalRuntimeDeps;

  # Keep user-level Python overlays from contaminating the packaged CLI. Sergio's
  # Hermes profile may export PYTHONPATH for Hermes itself; mixing that py312
  # tree into this py313 application breaks imports such as pydantic-core.
  makeWrapperArgs = [
    "--unset"
    "PYTHONPATH"
  ];

  pythonImportsCheck = [
    "mnemosyne"
  ]
  ++ lib.optionals enableCompression [ "rust_cave_001" ]
  ++ lib.optionals enableFastembed [ "fastembed" ]
  ++ lib.optionals enableSqliteVec [ "sqlite_vec" ]
  ++ lib.optionals enableNumpy [ "numpy" ]
  ++ lib.optionals enableHuggingfaceHub [ "huggingface_hub" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne --help >/dev/null
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne stats >/dev/null
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne python - <<'PY'
    from mnemosyne.integrations.memory_browser import _build_html, create_app

    html = _build_html([], query="test")
    assert "No memories found." in html
    assert "--bg" in html
    assert 'value="test"' in html
    app = create_app(banks=["default"], default_bank="default")
    assert app.title == "Mnemosyne Browser"
    PY
    ${lib.optionalString enableCompression ''
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
    HERMES_HOME=$TMPDIR/hermes $out/bin/mnemosyne-install --help >/dev/null
    test ! -e $TMPDIR/hermes/plugins/mnemosyne
    runHook postInstallCheck
  '';

  passthru = {
    category = "AI Assistants";
    inherit rustCave001;
    optionalRuntimeDependencies = {
      compression = enableCompression;
      fastembed = enableFastembed;
      sqlite-vec = enableSqliteVec;
      numpy = enableNumpy;
      huggingface-hub = enableHuggingfaceHub;
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
}
