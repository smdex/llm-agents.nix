#!/usr/bin/env python3
"""Mirror GitLab main/chiki to GitHub; bootstrap both maintenance branches manually.

Set GITLAB_MIRROR_URL, GITHUB_MIRROR_URL and masked GITHUB_MIRROR_TOKEN.
GitLab credentials must have permission to update the maintenance branches. Run
only one mirror job at a time; protect the maintenance branches from other writers.
"""

import base64
import os
import subprocess
import sys
import tempfile
from pathlib import Path
from urllib.parse import urlsplit

BRANCHES = ("main", "chiki")


def git(repo: Path, *args: str, env: dict[str, str] | None = None) -> str:
    """Run git without exposing diagnostics or credentials."""
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    if result.returncode:
        msg = f"git {args[0]} failed"
        raise RuntimeError(msg)
    return result.stdout.strip()


def mirror(gitlab: str, github: str, env: dict[str, str]) -> None:
    """Mirror source branches and advance their markers."""
    source_env = env.copy()
    source_env.pop("GITHUB_MIRROR_TOKEN", None)
    source_env.pop("GIT_ASKPASS", None)
    if gitlab.startswith("https://"):
        url = urlsplit(gitlab)
        basic = base64.b64encode(f"oauth2:{env['GL_TOKEN']}".encode()).decode()
        source_env.update(
            GIT_CONFIG_COUNT="1",
            GIT_CONFIG_KEY_0=f"http.{url.scheme}://{url.netloc}/.extraHeader",
            GIT_CONFIG_VALUE_0=f"Authorization: Basic {basic}",
        )
    with tempfile.TemporaryDirectory(prefix="github-mirror-") as tmp:
        repo = Path(tmp)
        git(repo, "init", "--bare", "--quiet", env=env)

        def fetch_source() -> tuple[dict[str, str], dict[str, str], dict[str, str]]:
            refs = [f"+refs/heads/{b}:refs/source/{b}" for b in BRANCHES]
            refs += [
                f"+refs/heads/maintenance/github-{b}:refs/marker/{b}" for b in BRANCHES
            ]
            refs.append("+refs/heads/maintenance/github-intent-*:refs/intent/*")
            git(repo, "fetch", "--prune", "--no-tags", gitlab, *refs, env=source_env)
            intents = git(
                repo,
                "for-each-ref",
                "--format=%(refname:strip=2) %(objectname)",
                "refs/intent/",
                env=env,
            )
            return (
                {
                    b: git(repo, "rev-parse", f"refs/source/{b}", env=env)
                    for b in BRANCHES
                },
                {
                    b: git(repo, "rev-parse", f"refs/marker/{b}", env=env)
                    for b in BRANCHES
                },
                dict(line.split() for line in intents.splitlines()),
            )

        source, markers, intents = fetch_source()
        git(
            repo,
            "merge-base",
            "--is-ancestor",
            source["main"],
            source["chiki"],
            env=env,
        )
        git(
            repo,
            "fetch",
            "--no-tags",
            github,
            *(f"+refs/heads/{b}:refs/follower/{b}" for b in BRANCHES),
            env=env,
        )
        follower = {
            b: git(repo, "rev-parse", f"refs/follower/{b}", env=env) for b in BRANCHES
        }
        if intents and set(intents) != set(BRANCHES):
            msg = "incomplete mirror intent"
            raise RuntimeError(msg)
        if follower != markers and (not intents or follower != intents):
            msg = "GitHub diverged from the recorded mirror tips"
            raise RuntimeError(msg)
        if fetch_source() != (source, markers, intents):
            msg = "GitLab source or markers changed during mirroring"
            raise RuntimeError(msg)

        if intents:
            if follower == markers and follower != intents:
                git(
                    repo,
                    "push",
                    "--atomic",
                    *(
                        f"--force-with-lease=refs/heads/{b}:{follower[b]}"
                        for b in BRANCHES
                    ),
                    github,
                    *(f"{intents[b]}:refs/heads/{b}" for b in BRANCHES),
                    env=env,
                )
                follower = intents.copy()
            git(
                repo,
                "push",
                "--atomic",
                *(
                    f"--force-with-lease=refs/heads/maintenance/github-{b}:{markers[b]}"
                    for b in BRANCHES
                ),
                *(
                    f"--force-with-lease=refs/heads/maintenance/github-intent-{b}:{intents[b]}"
                    for b in BRANCHES
                ),
                gitlab,
                *(f"{follower[b]}:refs/heads/maintenance/github-{b}" for b in BRANCHES),
                *(f":refs/heads/maintenance/github-intent-{b}" for b in BRANCHES),
                env=source_env,
            )
            markers = follower.copy()

        if follower != source:
            git(
                repo,
                "push",
                "--atomic",
                *(
                    f"--force-with-lease=refs/heads/maintenance/github-intent-{b}:"
                    for b in BRANCHES
                ),
                *(
                    f"--force-with-lease=refs/heads/maintenance/github-{b}:{markers[b]}"
                    for b in BRANCHES
                ),
                gitlab,
                *(f"{markers[b]}:refs/heads/maintenance/github-{b}" for b in BRANCHES),
                *(
                    f"{source[b]}:refs/heads/maintenance/github-intent-{b}"
                    for b in BRANCHES
                ),
                env=source_env,
            )
            git(
                repo,
                "push",
                "--atomic",
                *(f"--force-with-lease=refs/heads/{b}:{follower[b]}" for b in BRANCHES),
                github,
                *(f"{source[b]}:refs/heads/{b}" for b in BRANCHES),
                env=env,
            )
            git(
                repo,
                "push",
                "--atomic",
                *(
                    f"--force-with-lease=refs/heads/maintenance/github-{b}:{markers[b]}"
                    for b in BRANCHES
                ),
                *(
                    f"--force-with-lease=refs/heads/maintenance/github-intent-{b}:{source[b]}"
                    for b in BRANCHES
                ),
                gitlab,
                *(f"{source[b]}:refs/heads/maintenance/github-{b}" for b in BRANCHES),
                *(f":refs/heads/maintenance/github-intent-{b}" for b in BRANCHES),
                env=source_env,
            )


def main() -> int:
    """Validate configuration and run the mirror."""
    try:
        gitlab = os.environ["GITLAB_MIRROR_URL"]
        github = os.environ["GITHUB_MIRROR_URL"]
        token = os.environ["GITHUB_MIRROR_TOKEN"]
        gl_token = os.environ["GL_TOKEN"]
        url = urlsplit(github)
        if (
            url.scheme != "https"
            or url.netloc != "github.com"
            or url.path not in ("/smdex/llm-agents.nix", "/smdex/llm-agents.nix.git")
            or url.query
            or url.fragment
            or not token
        ):
            msg = "invalid GitHub mirror URL or token"
            raise ValueError(msg)  # noqa: TRY301
        source_url = urlsplit(gitlab)
        if (
            source_url.scheme != "https"
            or not source_url.hostname
            or source_url.username is not None
            or source_url.password is not None
            or source_url.hostname == "github.com"
            or not source_url.path.strip("/")
            or source_url.query
            or source_url.fragment
            or not gl_token
        ):
            msg = "invalid GitLab mirror URL or token"
            raise ValueError(msg)  # noqa: TRY301
        _ = source_url.port
        with tempfile.TemporaryDirectory(prefix="github-askpass-") as tmp:
            askpass = Path(tmp) / "askpass"
            askpass.write_text(
                '#!/bin/sh\ncase "$1" in *sername*) echo x-access-token;; *) printf "%s\\n" "$GITHUB_MIRROR_TOKEN";; esac\n'
            )
            askpass.chmod(0o700)
            env = os.environ.copy()
            for key in list(env):
                if (
                    key.startswith(("GIT_CONFIG_", "GIT_TRACE"))
                    or key == "GIT_CURL_VERBOSE"
                ):
                    env.pop(key)
            env.update(
                GIT_ASKPASS=str(askpass),
                GIT_TERMINAL_PROMPT="0",
                GIT_CONFIG_NOSYSTEM="1",
                GIT_CONFIG_GLOBAL=os.devnull,
            )
            mirror(gitlab, github, env)
    except (KeyError, ValueError, RuntimeError, OSError):
        print(
            "Mirror failed; check configuration and repository state", file=sys.stderr
        )
        return 1
    else:
        print("GitHub mirror updated")
        return 0


if __name__ == "__main__":
    sys.exit(main())
