{
  lib,
  flake,
  python3,
  fetchFromGitHub,
}:

python3.pkgs.buildPythonApplication rec {
  pname = "mnemosyne-memory";
  version = "3.10.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "AxDSan";
    repo = "mnemosyne";
    tag = "v${version}";
    hash = "sha256-hpNnKc8ZNbqcy9X4Yu/4zMGEW7TCyT9aEfRv03ffuig=";
  };

  postPatch = ''
        substituteInPlace mnemosyne/install.py \
          --replace-fail '    except Exception as e:
            print(f"⚠️  Verification skipped: {e}")
            return False
    ' '    except ModuleNotFoundError as e:
            if e.name == "plugins":
                target = hermes_home / "plugins" / "mnemosyne"
                if target.exists():
                    print("⚠️  Hermes Python modules are not importable from this installer process.")
                    print(f"   Plugin link verified: {target} -> {target.resolve()}")
                    print("   Run `hermes memory status` after install to verify inside Hermes itself.")
                    return True
            print(f"⚠️  Verification skipped: {e}")
            return False
        except Exception as e:
            print(f"⚠️  Verification skipped: {e}")
            return False
    '

        substituteInPlace mnemosyne/install.py \
          --replace-fail '    print("🌀 Mnemosyne Hermes Installer")
    ' '    if any(arg in ("-h", "--help") for arg in sys.argv[1:]):
            print("Usage: mnemosyne-install [--help] [--uninstall]")
            print()
            print("Install Mnemosyne as a Hermes memory provider.")
            print()
            print("Options:")
            print("  -h, --help     Show this help message and exit")
            print("  --uninstall    Remove the Mnemosyne Hermes plugin link and reset config")
            return
        if "--uninstall" in sys.argv[1:]:
            uninstall()
            return
        unknown = [arg for arg in sys.argv[1:] if arg != "--uninstall"]
        if unknown:
            print(f"Unknown option: {unknown[0]}", file=sys.stderr)
            print("Run `mnemosyne-install --help` for usage.", file=sys.stderr)
            sys.exit(2)

        print("🌀 Mnemosyne Hermes Installer")
    '
  '';

  build-system = with python3.pkgs; [
    setuptools
    wheel
  ];

  dependencies = with python3.pkgs; [
    anyio
    cryptography
    fastapi
    fastembed
    mcp
    sqlite-vec
    uvicorn
  ];

  # Keep user-level Python overlays from contaminating the packaged CLI. Sergio's
  # Hermes profile may export PYTHONPATH for Hermes itself; mixing that py312
  # tree into this py313 application breaks imports such as pydantic-core.
  makeWrapperArgs = [
    "--unset"
    "PYTHONPATH"
  ];

  pythonImportsCheck = [ "mnemosyne" ];

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne --help >/dev/null
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne $out/bin/mnemosyne stats >/dev/null
    MNEMOSYNE_DATA_DIR=$TMPDIR/mnemosyne python - <<'PY'
    from mnemosyne.integrations.memory_browser import create_app

    app = create_app(banks=["default"], default_bank="default")
    assert app.title == "Mnemosyne Browser"
    PY
    HERMES_HOME=$TMPDIR/hermes $out/bin/mnemosyne-install --help >/dev/null
    test ! -e $TMPDIR/hermes/plugins/mnemosyne
    runHook postInstallCheck
  '';

  passthru.category = "AI Assistants";

  meta = with lib; {
    description = "Universal Hermes-first SQLite memory layer for AI agents with MCP, sync, and vector search support";
    homepage = "https://github.com/AxDSan/mnemosyne";
    changelog = "https://github.com/AxDSan/mnemosyne/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "mnemosyne";
    platforms = platforms.all;
  };
}
