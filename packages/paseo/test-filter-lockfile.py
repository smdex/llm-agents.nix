"""Run with python3 packages/paseo/test-filter-lockfile.py."""

# ruff: noqa: INP001, S101 -- standalone assertion-based regression check
import runpy
from pathlib import Path

script = runpy.run_path(str(Path(__file__).with_name("filter-lockfile.py")))
matches = script["matches"]
filter_packages = script["filter_packages"]

assert matches([], "linux")
assert matches(["any"], "linux")
assert matches(["linux", "darwin"], "linux")
assert matches(["!win32"], "linux")
assert not matches(["!linux"], "linux")
assert not matches(["linux", "!linux"], "linux")
assert not matches(["darwin"], "linux")

packages = {
    "": {"workspaces": ["packages/server"]},
    "packages/server": {"dependencies": {"required": "1"}},
    "node_modules/required": {"os": ["win32"]},
    "node_modules/linux": {"optional": True, "os": ["linux"], "cpu": ["x64"]},
    "node_modules/arm": {"optional": True, "cpu": ["arm64"]},
    "node_modules/mac": {"optional": True, "os": ["darwin"]},
    "node_modules/mac/node_modules/child": {"optional": True},
    "node_modules/portable": {"optional": True},
}
filtered = filter_packages(packages, "linux", "x64")
assert set(filtered) == {
    "",
    "packages/server",
    "node_modules/required",
    "node_modules/linux",
    "node_modules/portable",
}
assert filter_packages(filtered, "linux", "x64") == filtered
assert "node_modules/mac" in packages
print("Platform filtering checks passed")
