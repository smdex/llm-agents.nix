{
  pkgs,
  perSystem,
  flake,
  dependencyGroups ? [
    "gateway"
    "misc"
    "audio"
  ],
  extraDependencyGroups ? [ ],
  extraPythonPackages ? (_: [ ]),
  ...
}:
pkgs.callPackage ./package.nix {
  inherit
    flake
    dependencyGroups
    extraDependencyGroups
    extraPythonPackages
    ;
  inherit (pkgs) python3;
  inherit (perSystem.self) versionCheckHomeHook;
}
