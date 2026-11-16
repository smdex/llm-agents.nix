"""Exercise targeted build selection without running Nix or modifying a checkout."""

import os
import subprocess
import unittest
from pathlib import Path

SCRIPT = Path(__file__).with_name("validate-mr.sh")


class ValidateMrTest(unittest.TestCase):
    def test_targeted_build_selection(self) -> None:
        for source, target, package in [
            ("ci-fix/vtcode", "main", "vtcode"),
            ("update/vtcode", "main", "vtcode"),
            ("update-branch/chiki/jcode", "chiki", "jcode"),
            ("ci-fix/vtcode", "chiki", None),
            ("ci-fix/../vtcode", "main", None),
            ("ci-fix/vtcode/extra", "main", None),
            ("ci-fix/", "main", None),
            ("feature/vtcode", "main", None),
        ]:
            with self.subTest(source=source, target=target):
                result = subprocess.run(
                    [
                        "bash",
                        "-c",
                        'git() { return 0; }; nix() { printf "NIX %s\\n" "$*"; }; source "$1"',
                        "validate-test",
                        str(SCRIPT),
                    ],
                    env={
                        **os.environ,
                        "MR_SOURCE_BRANCH": source,
                        "MR_TARGET_BRANCH": target,
                    },
                    check=True,
                    text=True,
                    capture_output=True,
                )
                builds = [
                    line
                    for line in result.stdout.splitlines()
                    if line.startswith("NIX build ")
                ]
                self.assertEqual(
                    builds,
                    [f"NIX build --accept-flake-config --no-link .#{package}"]
                    if package
                    else [],
                )


if __name__ == "__main__":
    unittest.main()
