# Run the CI automation library's stdlib unittest modules under the flake
# check (mirrors updater-tests.nix; kept separate so no upstream-owned file
# is modified by the fork). Discovery picks up every scripts/ci/*_test.py.
# vibe-kanban's custom updater test runs alongside: its update.py imports the
# scripts/updater library, so the packages tree is staged next to scripts/.
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
    mkdir -p packages
    cp -r ${flake}/scripts scripts
    cp -r ${flake}/packages/vibe-kanban packages/
    chmod -R +w scripts packages
    cd scripts
    export HOME=$TMPDIR
    export PYTHONDONTWRITEBYTECODE=1
    python3 -m unittest discover -s ci -p '*_test.py' -t . -v
    PYTHONPATH=$PWD python3 ../packages/vibe-kanban/update_test.py -v
    touch $out
  ''
