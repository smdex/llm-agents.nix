{
  pkgs,
  flake,
  ...
}: let
  python = pkgs.python3.pkgs;
  rustCave001 = python.callPackage ./rust-cave.nix {inherit flake;};
  mnemosyne = python.callPackage ./package.nix {inherit flake rustCave001 mnemosyne-hermes;};
  mnemosyne-memory = python.toPythonApplication mnemosyne;
  mnemosyne-hermes = python.callPackage ./hermes-plugin.nix {inherit mnemosyne;};
in mnemosyne-memory
