#!/usr/bin/env python3
"""Discover packages and flake inputs for update checking.

Discovers packages with version attributes and, when requested, flake inputs.
Fork automation can restrict package updates to packages that exist in this
repository but are absent from upstream/main.
"""

import json
import logging
import os
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from lib import write_output

log = logging.getLogger(__name__)

NIX_EXPR = """
let
  config = builtins.fromJSON (builtins.getEnv "DISCOVERY_CONFIG");
  flake = builtins.getFlake (toString ./.);
  pkgs = flake.packages.${config.system};
  isHidden = pkg: pkg.passthru.hideFromDocs or false;
  updateEvenIfHidden = pkg: pkg.passthru.updateEvenIfHidden or false;
  shouldDiscover = pkg: !(isHidden pkg) || updateEvenIfHidden pkg;
  getVersion = name:
    if pkgs ? ${name} && pkgs.${name} ? version && shouldDiscover pkgs.${name}
    then { inherit name; value = pkgs.${name}.version; }
    else null;
in
  if config.filter == null then
    builtins.mapAttrs (name: pkg:
      if pkg ? version && shouldDiscover pkg then pkg.version else null
    ) pkgs
  else
    builtins.listToAttrs
      (builtins.filter (x: x != null) (map getVersion config.filter))
"""


@dataclass(frozen=True, slots=True)
class MatrixItem:
    """Represents an item in the update matrix."""

    type: str
    name: str
    current_version: str

    def to_dict(self) -> dict[str, str]:
        """Convert to dictionary for JSON serialization."""
        return {
            "type": self.type,
            "name": self.name,
            "current_version": self.current_version,
        }


def parse_bool(value: str | None, *, default: bool = False) -> bool:
    """Parse common CI boolean spellings."""
    if value is None or value == "":
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def run_git(args: list[str]) -> subprocess.CompletedProcess[str]:
    """Run a git command and capture output for discovery decisions."""
    return subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def upstream_package_names(upstream_ref: str) -> set[str]:
    """Return package directory names present at the upstream ref."""
    result = run_git(["ls-tree", "-d", "--name-only", f"{upstream_ref}:packages"])
    if result.returncode != 0:
        log.error(
            "::error::failed to list packages at %s: %s",
            upstream_ref,
            result.stderr.strip(),
        )
        sys.exit(1)
    return {line.strip() for line in result.stdout.splitlines() if line.strip()}


def filter_added_packages(
    packages: list[str] | None,
    *,
    upstream_ref: str,
) -> list[str] | None:
    """Keep only packages whose directory is absent from upstream/main."""
    upstream_packages = upstream_package_names(upstream_ref)

    if packages is None:
        local_packages = sorted(
            path.name
            for path in Path("packages").iterdir()
            if path.is_dir() and path.name not in upstream_packages
        )
        log.info(
            "Restricting package discovery to %d fork-added package(s)",
            len(local_packages),
        )
        for name in local_packages:
            log.info("Fork-added package: %s", name)
        return local_packages

    added_packages = []
    for name in packages:
        if name in upstream_packages:
            log.info("Skipping %s (present in upstream)", name)
            continue
        added_packages.append(name)
    return added_packages


def discover_packages(
    packages_filter: list[str] | None, system: str
) -> list[MatrixItem]:
    """Discover packages with version attributes in a single nix eval."""
    log.info("Discovering packages...")

    config = json.dumps({"system": system, "filter": packages_filter})
    result = subprocess.run(
        ["nix", "eval", "--json", "--impure", "--expr", NIX_EXPR],
        capture_output=True,
        text=True,
        env={**os.environ, "DISCOVERY_CONFIG": config},
        check=False,
    )
    if result.returncode != 0:
        log.error("Failed to evaluate packages: %s", result.stderr)
        return []

    versions: dict[str, str | None] = json.loads(result.stdout)
    items = [
        MatrixItem(type="package", name=name, current_version=version)
        for name, version in sorted(versions.items())
        if version is not None
    ]

    if packages_filter is None:
        for name, version in sorted(versions.items()):
            if version is None:
                log.info("Skipping %s (no version attribute)", name)
    else:
        found = set(versions.keys())
        for pkg in packages_filter:
            if pkg not in found:
                log.warning("Package %s not found or has no version", pkg)

    return items


def discover_flake_inputs(inputs_filter: list[str] | None) -> list[MatrixItem]:
    """Discover flake inputs from flake.lock."""
    log.info("Discovering flake inputs...")

    lock_path = Path("flake.lock")
    if not lock_path.exists():
        log.info("No flake.lock found, skipping input updates")
        return []

    nodes: dict[str, dict[str, object]] = json.loads(lock_path.read_text()).get(
        "nodes", {}
    )
    input_names = inputs_filter or sorted(k for k in nodes if k != "root")

    items: list[MatrixItem] = []
    for name in input_names:
        node = nodes.get(name)
        if node is None:
            continue
        locked = node.get("locked")
        rev = (
            locked.get("rev", "unknown")[:8] if isinstance(locked, dict) else "unknown"
        )
        items.append(MatrixItem(type="flake-input", name=name, current_version=rev))

    return items


def write_matrix(matrix_items: list[MatrixItem]) -> None:
    """Write matrix JSON and has-updates flag to GITHUB_OUTPUT or log summary."""
    has_updates = len(matrix_items) > 0
    matrix = {"include": [item.to_dict() for item in matrix_items]}
    matrix_json = json.dumps(matrix, separators=(",", ":"))

    write_output("matrix", matrix_json)
    write_output("has-updates", str(has_updates).lower())

    if not os.environ.get("GITHUB_OUTPUT"):
        log.info("")
        log.info("=== Pretty-printed Matrix ===")
        log.info("%s", json.dumps(matrix, indent=2))
        if has_updates:
            type_counts: dict[str, int] = {}
            for item in matrix_items:
                type_counts[item.type] = type_counts.get(item.type, 0) + 1
            log.info("")
            log.info("=== Summary ===")
            for item_type, count in sorted(type_counts.items()):
                log.info("  %d %s", count, item_type)


def main() -> None:
    """Discover packages and flake inputs, output matrix for GitHub Actions."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")

    packages_env = os.environ.get("PACKAGES", "")
    inputs_env = os.environ.get("INPUTS", "")
    include_inputs = parse_bool(os.environ.get("INCLUDE_INPUTS"), default=True)
    added_packages_only = parse_bool(os.environ.get("ADDED_PACKAGES_ONLY"))
    upstream_ref = os.environ.get("UPSTREAM_REF", "upstream/main")
    system = os.environ.get("SYSTEM", "x86_64-linux")

    packages_filter = packages_env.split() or None
    if added_packages_only:
        packages_filter = filter_added_packages(
            packages_filter,
            upstream_ref=upstream_ref,
        )

    log.info("=== Discovery Configuration ===")
    log.info("PACKAGES: %s", " ".join(packages_filter or []) or "<all>")
    log.info("ADDED_PACKAGES_ONLY: %s", str(added_packages_only).lower())
    log.info("UPSTREAM_REF: %s", upstream_ref if added_packages_only else "<unused>")
    log.info("INPUTS: %s", inputs_env or ("<all>" if include_inputs else "<disabled>"))
    log.info("")

    matrix_items = [
        *discover_packages(packages_filter, system),
        *(discover_flake_inputs(inputs_env.split() or None) if include_inputs else []),
    ]

    log.info("")
    log.info("=== Discovery Results ===")
    if matrix_items:
        log.info("Found %d item(s) to update", len(matrix_items))
    else:
        log.info("No items to update")

    write_matrix(matrix_items)


if __name__ == "__main__":
    main()
