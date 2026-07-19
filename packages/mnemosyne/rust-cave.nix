{
  flake,
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  rustPlatform,
  rustc,
  cargo,
}:

buildPythonPackage (finalAttrs: {
  pname = "rust-cave-001";
  version = "0.5.0";
  pyproject = true;
  src = fetchFromGitHub {
    owner = "ether-btc";
    repo = "rust-cave-001";
    tag = "v${finalAttrs.version}";
    hash = "sha256-nEILOoWgmlvKzlgDUGwL4gWgwnDaV8fGu5b1N8ElXt4=";
  };

  cargoDeps = rustPlatform.fetchCargoVendor {
    inherit (finalAttrs) pname version src;
    hash = "sha256-p54YmdzLC2cOZA7qgwx9FwIyoqB6RcX9ocf/sWFVYSY=";
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
    changelog = "https://github.com/ether-btc/rust-cave-001/releases/tag/v${finalAttrs.version}";
    license = licenses.mit;
    sourceProvenance = with sourceTypes; [ fromSource ];
    maintainers = with flake.lib.maintainers; [ smdex ];
    platforms = platforms.all;
  };
})
