# Run the CI automation library's stdlib unittest modules under the flake
# check (mirrors updater-tests.nix; kept separate so no upstream-owned file
# is modified by the fork). Discovery picks up every scripts/ci/*_test.py.
{
  pkgs,
  flake,
}:
pkgs.runCommand "ci-tests-check"
  {
    # git + bash: the confinement and fork-package tests drive real git
    # repositories in $TMPDIR.
    nativeBuildInputs = [
      pkgs.python3
      pkgs.git
      pkgs.bash
      pkgs.jq
    ];
  }
  ''
    cp -r ${flake}/scripts scripts
    chmod -R +w scripts
    cd scripts
    export HOME=$TMPDIR
    export PYTHONDONTWRITEBYTECODE=1
    python3 -m unittest discover -s ci -p '*_test.py' -t . -v
    touch $out
  ''
