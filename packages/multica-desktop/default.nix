{
  pkgs,
  flake,
  perSystem,
  ...
}:
pkgs.callPackage ./package.nix {
  inherit flake;
  inherit (perSystem.self) multica;
  autoPatchelfHook = perSystem.self.formatelf;
}
