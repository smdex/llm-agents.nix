{
  lib,
  flake,
  python3,
  fetchFromGitHub,
  fetchPypi,
  versionCheckHook,
  versionCheckHomeHook,
}:

let
  # milvus-lite is not in nixpkgs. Since 3.x it is a pure-Python wheel
  # (py3-none-any) — the older 2.x line shipped a bundled Go native binary, but
  # 3.x is a faiss/pyarrow-backed reimplementation with no native code. Vendor
  # it inline so the memsearch closure gets a working local Milvus.
  milvus-lite = python3.pkgs.buildPythonPackage rec {
    pname = "milvus-lite";
    version = "3.2.0";
    pyproject = true;

    src = fetchPypi {
      pname = "milvus_lite";
      inherit version;
      hash = "sha256-1nNdelvLFP7SzJpC2oTXOW/vAECg98LRys6fITSSVXE=";
    };

    build-system = with python3.pkgs; [ hatchling ];

    dependencies = with python3.pkgs; [
      faiss-cpu
      grpcio
      numpy
      pyarrow
    ];

    doCheck = false;

    meta = with lib; {
      description = "Lightweight pure-Python Milvus for local development";
      homepage = "https://github.com/milvus-io/milvus-lite";
      license = licenses.asl20;
      sourceProvenance = with sourceTypes; [ fromSource ];
      platforms = platforms.unix;
    };
  };
in
python3.pkgs.buildPythonApplication rec {
  pname = "memsearch";
  version = "0.4.17";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "zilliztech";
    repo = "memsearch";
    tag = "v${version}";
    hash = "sha256-pqc8vqSSJAVf0tU8B9sgdI4iOL6XZz2zhhOBzeuNmr4=";
  };

  build-system = with python3.pkgs; [ hatchling ];

  nativeBuildInputs = with python3.pkgs; [ pythonRelaxDepsHook ];

  # memsearch pins setuptools<81, but its source never imports setuptools or
  # pkg_resources — the constraint is vestigial. Relax it so nixpkgs'
  # current setuptools satisfies the runtime-deps check.
  pythonRelaxDeps = [ "setuptools" ];

  dependencies = with python3.pkgs; [
    pymilvus
    milvus-lite
    click
    watchdog
    pathspec
    setuptools
    tomli-w
    openai
  ];

  pythonImportsCheck = [ "memsearch" ];

  doInstallCheck = true;
  nativeInstallCheckInputs = [
    versionCheckHook
    versionCheckHomeHook
  ];
  versionCheckProgramArg = [ "--version" ];

  passthru.category = "Utilities";

  meta = with lib; {
    description = "Persistent, unified semantic memory layer for AI agents (Milvus-backed vector search)";
    homepage = "https://github.com/zilliztech/memsearch";
    changelog = "https://github.com/zilliztech/memsearch/releases/tag/v${version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    mainProgram = "memsearch";
    platforms = platforms.unix;
  };
}
