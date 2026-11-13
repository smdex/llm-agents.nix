#!/usr/bin/env nix
#! nix shell --inputs-from .# nixpkgs#python3 nixpkgs#git nixpkgs#coreutils --command python3
"""Drive fork-only package updates and publish them as GitLab MRs.

Fork-only packages are the directory set difference ``packages/`` on the
fork's default branch minus ``packages/`` on upstream — NOT a git-history
diff: shared upstream packages that this fork modifies are not fork
additions and stay on the upstream update flow.

The updater itself is reused verbatim from ``.github/ci/discovery.py``
and ``.github/ci/update.py`` (upstream-owned, unmodified). This driver
adds:

* credential isolation — the updater runs with every token stripped
  from its environment (it needs none: unauthenticated APIs only);
* branch bookkeeping — reuse/rebase ``update/<package>`` branches;
* a downgrade guard — the fork updater stack can regress versions, so
  publishing is skipped unless the new version orders above the old;
* MR publishing via :mod:`gitlab_mr`.

Exit codes: 0 = nothing to do or everything published; 1 = at least one
package failed to update (other packages still publish, and the merge
stage still runs — use allow_failure on this job); 2 = systemic failure
(discovery or the fork package list could not be computed).
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Callable

try:
    from . import gitlab_mr
except ImportError:  # executed as a script
    import gitlab_mr
try:
    from .gitlab_api import CREDENTIAL_VARS, resolve_config
except ImportError:  # executed as a script
    from gitlab_api import CREDENTIAL_VARS, resolve_config

log = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[2]

# ".github/ci" and "scripts/ci" are copied out before the updater runs so
# a tampered update.py cannot rewrite the code that holds the token
# later (same scheme as the GitHub workflow's "Stash CI scripts" step).
STASHED_DIRS = (".github/ci", "scripts/ci")


def run(
    cmd: list[str],
    *,
    env: dict[str, str] | None = None,
    check: bool = True,
) -> subprocess.CompletedProcess[str]:
    """Run a subprocess from the repository root."""
    return subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        env=env,
        text=True,
        check=check,
        capture_output=True,
    )


def sanitized_updater_env(extra: dict[str, str] | None = None) -> dict[str, str]:
    """Build the updater's environment with every credential removed.

    Also disables git hook execution and fsmonitor for the updater's own
    git calls (belt and suspenders on top of update.py's bubblewrap
    sandbox).
    """
    env = dict(os.environ)
    if extra:
        env.update(extra)
    # Strip credentials last so no caller-supplied value can reintroduce
    # them — not even via `extra`.
    env = {
        key: value
        for key, value in env.items()
        if key not in CREDENTIAL_VARS
        and not any(
            part in key.upper()
            for part in ("TOKEN", "PASSWORD", "SECRET", "PRIVATE_KEY")
        )
        and not key.startswith("GIT_CONFIG_")
        and key
        not in ("CI_REPOSITORY_URL", "CI_REPO_CLONE_URL", "GIT_ASKPASS", "SSH_ASKPASS")
    }
    env.update(
        {
            "GIT_CONFIG_COUNT": "2",
            "GIT_CONFIG_KEY_0": "core.hooksPath",
            "GIT_CONFIG_VALUE_0": "/dev/null",
            "GIT_CONFIG_KEY_1": "core.fsmonitor",
            "GIT_CONFIG_VALUE_1": "false",
        }
    )
    return env


def python_in_devshell(script: Path, *args: str) -> list[str]:
    """Command running a python script inside the devshell's toolset.

    The devshell provides nix-update/bun/node for the updater but no
    python, so wrap with nix shell for python3 (the GitHub runners rely
    on their preinstalled python; CI containers cannot).
    """
    return [
        "nix",
        "develop",
        "--accept-flake-config",
        "-c",
        "nix",
        "shell",
        "--inputs-from",
        str(REPO_ROOT),
        "nixpkgs#python3",
        "--command",
        "python3",
        str(script),
        *args,
    ]


def stash_ci_scripts(target: Path) -> Path:
    """Copy the trusted CI scripts out of the (soon untrusted) tree."""
    for source in STASHED_DIRS:
        destination = target / source
        if destination.exists():
            shutil.rmtree(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(REPO_ROOT / source, destination)
    stashed_ci = target / ".github" / "ci"
    shutil.copytree(
        REPO_ROOT / "scripts" / "updater", stashed_ci / "updater", dirs_exist_ok=True
    )
    return stashed_ci


def fork_packages(*, explicit: bool = False, branch: str | None = None) -> list[str]:
    """Fork-added package names (directory set difference vs upstream)."""
    env = dict(os.environ)
    if explicit:
        env.pop("FORK_UPDATE_PACKAGES", None)
    if branch is not None:
        env["FORK_REF"] = f"origin/{branch}"
    result = run(
        ["bash", str(REPO_ROOT / "scripts" / "ci" / "fork-packages.sh")],
        env=env,
        check=False,
    )
    if result.returncode != 0:
        log.error("fork-packages.sh failed: %s", result.stderr.strip())
        raise SystemExit(2)
    packages = [line for line in result.stdout.splitlines() if line.strip()]
    log.info("Fork-only packages (%d): %s", len(packages), " ".join(packages))
    return packages


def discover_updates(packages: list[str], stashed_ci: Path) -> list[dict[str, str]]:
    """Reuse .github/ci/discovery.py to build the update matrix."""
    with tempfile.NamedTemporaryFile("w", delete=False) as output_file:
        output_path = output_file.name
    result = run(
        python_in_devshell(stashed_ci / "discovery.py"),
        env=sanitized_updater_env(
            {
                "PACKAGES": " ".join(packages),
                # Sentinel: no flake-input updates in the fork flow.
                "INPUTS": "none",
                "GITHUB_OUTPUT": output_path,
            }
        ),
        check=False,
    )
    if result.stdout:
        sys.stdout.write(result.stdout)
    if result.returncode != 0:
        log.error("discovery failed: %s", result.stderr.strip())
        raise SystemExit(2)

    outputs: dict[str, str] = {}
    with Path(output_path).open() as handle:
        for line in handle:
            key, _, value = line.strip().partition("=")
            if key:
                outputs[key] = value
    if not outputs.get("matrix"):
        return []
    matrix = json.loads(outputs["matrix"])
    items = matrix.get("include", [])
    discovered = {item["name"] for item in items}
    skipped = [package for package in packages if package not in discovered]
    if skipped:
        log.info(
            "Skipped by discovery (skipUpdate or no version): %s", " ".join(skipped)
        )
    return items


def prepare_branch(package: str, *, default_branch: str = "main") -> None:
    """Reuse the update/<package> branch, rebased onto the default branch.

    Port of the "Prepare update branch" step in update-flake.yml: manual
    fixups on an open MR branch carry into the work tree; a branch that
    no longer rebases cleanly is discarded.
    """
    branch = gitlab_mr.update_branch(package, default_branch)
    run(["git", "fetch", "origin", default_branch], env=resolve_config().git_env())
    # Start from a pristine work tree: a previous package's uncommitted
    # changes must not leak into this update (each GitHub matrix job gets
    # a fresh checkout; this loop emulates that).
    run(["git", "reset", "--hard", f"origin/{default_branch}"])
    run(["git", "clean", "-fd"])
    existing = run(
        [
            "git",
            "fetch",
            "origin",
            f"+refs/heads/{branch}:refs/remotes/origin/{branch}",
        ],
        env=resolve_config().git_env(),
        check=False,
    )
    if existing.returncode == 0:
        log.info("Reusing existing branch %s", branch)
        run(["git", "checkout", "-B", branch, f"origin/{branch}"])
        rebased = run(["git", "rebase", f"origin/{default_branch}"], check=False)
        if rebased.returncode != 0:
            log.warning("Rebase of %s failed; discarding stale branch", branch)
            run(["git", "rebase", "--abort"], check=False)
            run(["git", "reset", "--hard", f"origin/{default_branch}"])
    else:
        run(["git", "checkout", "-B", branch, f"origin/{default_branch}"])


def run_updater(
    package: str, stashed_ci: Path, *, default_branch: str = "main"
) -> dict[str, str] | None:
    """Run the stashed update.py for one package; None on failure."""
    with tempfile.NamedTemporaryFile("w", delete=False) as output_file:
        output_path = output_file.name
    env = sanitized_updater_env(
        {"GITHUB_OUTPUT": output_path, "UPDATE_BASE_REF": f"origin/{default_branch}"}
    )
    attempts = 3
    timeout = os.environ.get("PACKAGE_UPDATE_TIMEOUT", "1800")
    log.info("Updating %s (updater limit: %ss)", package, timeout)
    for attempt in range(attempts):
        # A failed updater may leave partial hashes or output behind. Reuse the
        # original branch, not those edits, when retrying a broken connection.
        Path(output_path).write_text("")
        result = run(
            [
                "timeout",
                "--kill-after=30s",
                f"{timeout}s",
                *python_in_devshell(stashed_ci / "update.py", "package", package),
            ],
            env=env,
            check=False,
        )
        if result.stdout:
            sys.stdout.write(result.stdout)
            sys.stdout.flush()
        if result.returncode == 0:
            break
        if result.returncode in (124, 137):
            log.error("updater timed out for %s after %ss", package, timeout)
            return None
        transient = any(
            error in result.stdout + result.stderr
            for error in (
                "http.client.IncompleteRead:",
                "ConnectionResetError:",
                "HTTP Error 502:",
                "HTTP Error 503:",
                "HTTP Error 504:",
            )
        )
        if not transient or attempt + 1 == attempts:
            log.error("updater failed for %s: %s", package, result.stderr.strip())
            return None
        log.warning(
            "Transient network failure for %s; retrying (%d/%d)",
            package,
            attempt + 2,
            attempts,
        )
        time.sleep(2 ** (attempt + 1))
        prepare_branch(package, default_branch=default_branch)

    outputs: dict[str, str] = {}
    with Path(output_path).open() as handle:
        for line in handle:
            key, _, value = line.strip().partition("=")
            if key:
                outputs[key] = value
    return outputs


def require_fork_only_companions(
    name: str, *, allowlist: frozenset[str] = frozenset(), default_branch: str = "main"
) -> None:
    """Do not let a fork updater delegate work to upstream-owned companions."""
    roots = gitlab_mr.allowed_roots(
        REPO_ROOT, name, base_ref=f"origin/{default_branch}"
    )
    upstream_ref = os.environ.get("UPSTREAM_REF", "main")
    upstream = run(
        [
            "git",
            "ls-tree",
            "-d",
            "--name-only",
            f"upstream/{upstream_ref}",
            "--",
            "packages/",
        ]
    )
    shared = {path.rstrip("/") for path in upstream.stdout.splitlines()}
    forbidden = [
        root
        for root in roots
        if root.rstrip("/") in shared
        and root.rstrip("/").removeprefix("packages/") not in allowlist
    ]
    if forbidden:
        message = f"refusing upstream-owned update companions: {forbidden}"
        raise RuntimeError(message)


def process_package(
    item: dict[str, str],
    *,
    stashed_ci: Path,
    publish: Callable[..., str] | None = None,
    default_branch: str = "main",
    allowlist: frozenset[str] = frozenset(),
) -> bool:
    """Update one package and publish its MR; False on failure."""
    if publish is None:
        publish = gitlab_mr.publish_package_update

    name = item["name"]
    current = item.get("current_version", "unknown")
    prepare_branch(name, default_branch=default_branch)
    require_fork_only_companions(
        name, allowlist=allowlist, default_branch=default_branch
    )

    outputs = run_updater(name, stashed_ci, default_branch=default_branch)
    if outputs is None:
        log.error("Update failed for %s", name)
        return False
    if outputs.get("updated") == "false":
        log.info("No package changes for %s (discovered version: %s)", name, current)
        return True
    if outputs.get("updated") != "true":
        log.error("Updater for %s did not report an update result", name)
        return False

    new = outputs.get("new_version", "unknown")
    allow_downgrade = os.environ.get("ALLOW_DOWNGRADE", "") == "1"
    if not allow_downgrade and gitlab_mr.is_downgrade(current, new):
        log.warning(
            "Refusing to publish downgrade for %s: %s -> %s "
            "(set ALLOW_DOWNGRADE=1 to override)",
            name,
            current,
            new,
        )
        return True

    action = publish(
        name=name,
        current_version=current,
        new_version=new,
        changelog_url=outputs.get("changelog", ""),
        default_branch=default_branch,
    )
    log.info("%s MR %s (%s -> %s)", action, name, current, new)
    return True


def select_packages(
    requested: list[str] | None, branch: str, fork_only: list[str]
) -> list[str]:
    """Validate explicit selections against package directories on the target branch."""
    if requested is None:
        return fork_only
    result = run(
        ["git", "ls-tree", "-d", "--name-only", f"origin/{branch}", "--", "packages/"]
    )
    available = {
        path.removeprefix("packages/").rstrip("/")
        for path in result.stdout.splitlines()
    }
    missing = set(requested) - available
    if missing:
        message = f"Unknown packages: {', '.join(sorted(missing))}"
        raise ValueError(message)
    return list(dict.fromkeys(requested))


def main() -> None:
    """Discover fork-only updates, run them, publish MRs."""
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--branch", default=None)
    parser.add_argument(
        "--packages",
        nargs="+",
        help="Explicit package allowlist, including shared overrides",
    )
    args = parser.parse_args()
    branch = args.branch or os.environ.get("DEFAULT_BRANCH", "main")
    run(["git", "check-ref-format", "--branch", branch])

    # The sync stage may have rewritten main after this pipeline's checkout.
    # Fetch it before discovery, and remove runner-persisted URL credentials.
    config = resolve_config()
    run(["git", "remote", "set-url", "origin", config.http_remote_url()])
    run(["git", "config", "user.name", os.environ.get("CI_BOT_NAME", "llm-agents-bot")])
    run(
        [
            "git",
            "config",
            "user.email",
            os.environ.get("CI_BOT_EMAIL", "llm-agents-bot@users.noreply.gitlab.local"),
        ]
    )
    run(
        [
            "git",
            "fetch",
            "origin",
            f"+refs/heads/{branch}:refs/remotes/origin/{branch}",
        ],
        env=config.git_env(),
    )
    run(["git", "checkout", "-B", branch, f"origin/{branch}"])
    fork_only = fork_packages(explicit=args.packages is not None, branch=branch)
    allowlist = frozenset(args.packages or ())
    packages = select_packages(args.packages, branch, fork_only)
    if not packages:
        log.info("No fork-only packages; nothing to do")
        return

    with tempfile.TemporaryDirectory(prefix="fork-update-") as temp_dir:
        stashed_ci = stash_ci_scripts(Path(temp_dir))
        items = discover_updates(packages, stashed_ci)
        if not items:
            log.info("No fork packages eligible for update")
            return

        failures = 0
        for item in items:
            if item["name"] not in packages:
                log.error("Discovery returned unselected package: %s", item["name"])
                failures += 1
                continue
            try:
                if not process_package(
                    item,
                    stashed_ci=stashed_ci,
                    default_branch=branch,
                    allowlist=allowlist,
                ):
                    failures += 1
            except SystemExit as exit_request:
                # e.g. confinement violation in gitlab_mr: fail this
                # package, keep the remaining ones running.
                log.exception("Update of %s aborted", item["name"])
                log.info("exit code: %s", exit_request)
                failures += 1
            except Exception:
                log.exception("Update of %s failed", item["name"])
                failures += 1
        if failures:
            log.error("%d package update(s) failed", failures)
            raise SystemExit(1)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        log.exception("Systemic fork update failure")
        raise SystemExit(2) from None
