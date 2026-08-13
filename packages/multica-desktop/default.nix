{
  pkgs,
  flake,
  perSystem,
  ...
}:
pkgs.callPackage ./package.nix {
  inherit flake;
  inherit (perSystem.self) multica;
  formatelf = perSystem.self.formatelf;
}
