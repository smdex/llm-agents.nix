"""Drop optional npm packages incompatible with the build's OS or CPU."""

# ruff: noqa: INP001 -- standalone build script, not an importable package
import json
import sys
from pathlib import Path
from typing import Any

LOCKFILE_VERSION = 3


def matches(allowed: list[str], target: str) -> bool:
    """Apply npm's platform allowlist and exclusion semantics."""
    if not allowed or "any" in allowed:
        return True
    if f"!{target}" in allowed:
        return False
    return target in allowed or all(value.startswith("!") for value in allowed)


def filter_packages(
    packages: dict[str, dict[str, Any]], os_name: str, cpu: str
) -> dict[str, dict[str, Any]]:
    """Keep required packages and target-compatible optional packages."""
    removed = {
        name
        for name, package in packages.items()
        if package.get("optional")
        and not (
            matches(package.get("os", []), os_name)
            and matches(package.get("cpu", []), cpu)
        )
    }
    return {
        name: package
        for name, package in packages.items()
        if name not in removed
        and not any(name.startswith(parent + "/node_modules/") for parent in removed)
    }


if __name__ == "__main__":
    path = Path("package-lock.json")
    lock = json.loads(path.read_text())
    if lock["lockfileVersion"] != LOCKFILE_VERSION:
        message = "Expected npm lockfile v3"
        raise ValueError(message)
    lock["packages"] = filter_packages(lock["packages"], *sys.argv[1:])
    path.write_text(json.dumps(lock, indent=2) + "\n")
