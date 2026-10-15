"""Minimal stdlib GitLab REST client for the fork maintenance scripts.

No third-party dependencies: these scripts must run inside the plain
``nixpkgs#python3`` environment provided by their nix shebang.

Credentials rule: the token is sent only via the ``Authorization``
header, never embedded in a URL, and error messages are sanitized so
the token cannot leak into logs.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Iterator
from typing import Any

log = logging.getLogger(__name__)

HTTP_OK_START = 200
HTTP_OK_END = 300

# Environment variables that must never reach updater subprocesses.
CREDENTIAL_VARS = (
    "GL_TOKEN",
    "GL_PUSH_TOKEN",
    "CI_JOB_TOKEN",
    "GITHUB_TOKEN",
    "GH_TOKEN",
)

Transport = Callable[
    [str, str, dict[str, str], bytes | None],
    tuple[int, bytes, dict[str, str]],
]


def urlopen_transport(
    url: str,
    method: str,
    headers: dict[str, str],
    body: bytes | None,
) -> tuple[int, bytes, dict[str, str]]:
    """Default transport: perform the HTTP request via urllib."""
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return (
                response.status,
                response.read(),
                {k.lower(): v for k, v in response.headers.items()},
            )
    except urllib.error.HTTPError as error:
        return (
            error.code,
            error.read(),
            {k.lower(): v for k, v in error.headers.items()},
        )


class GitLabApiError(RuntimeError):
    """A non-2xx GitLab API response (or transport failure)."""

    def __init__(self, method: str, path: str, status: int, detail: str) -> None:
        """Build an error that describes the request without secrets."""
        super().__init__(
            f"GitLab API {method} {path} failed with HTTP {status}: {detail}"
        )
        self.status = status


class GitLabApi:
    """Authenticated v4 API client with transparent pagination."""

    def __init__(
        self,
        base_url: str,
        token: str,
        *,
        transport: Transport = urlopen_transport,
        per_page: int = 100,
    ) -> None:
        """Store endpoint and credentials; no requests are made yet."""
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.transport = transport
        self.per_page = per_page

    def _request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, str] | None = None,
        json_body: dict[str, Any] | None = None,
    ) -> tuple[int, bytes, dict[str, str]]:
        """Perform one request and return status, body, and headers."""
        url = f"{self.base_url}/api/v4{path}"
        if params:
            url = f"{url}?{urllib.parse.urlencode(params)}"
        headers = {"Authorization": f"Bearer {self.token}"}
        body: bytes | None = None
        if json_body is not None:
            headers["Content-Type"] = "application/json"
            body = json.dumps(json_body).encode()
        return self.transport(url, method, headers, body)

    def request(
        self,
        method: str,
        path: str,
        *,
        params: dict[str, str] | None = None,
        json_body: dict[str, Any] | None = None,
    ) -> Any:  # noqa: ANN401 — JSON responses are inherently dynamic
        """Perform one request and decode its JSON response."""
        status, raw, _headers = self._request(
            method, path, params=params, json_body=json_body
        )
        if not HTTP_OK_START <= status < HTTP_OK_END:
            raise GitLabApiError(method, path, status, raw.decode(errors="replace"))
        if not raw:
            return None
        return json.loads(raw)

    def paginate(
        self,
        path: str,
        *,
        params: dict[str, str] | None = None,
    ) -> Iterator[Any]:
        """Yield items across all pages of a paginated GET endpoint."""
        params = dict(params or {})
        params["per_page"] = str(self.per_page)
        page = 1
        while True:
            params["page"] = str(page)
            status, raw, headers = self._request("GET", path, params=params)
            if not HTTP_OK_START <= status < HTTP_OK_END:
                method = "GET"
                detail = raw.decode(errors="replace")
                raise GitLabApiError(method, path, status, detail)
            items = json.loads(raw) if raw else []
            yield from items
            next_page = headers.get("x-next-page", "")
            if not next_page:
                return
            page = int(next_page)


def url_encoded_project(project_path: str) -> str:
    """Encode "group/repo" for use as a single URL path segment."""
    return urllib.parse.quote(project_path.strip("/"), safe="")


class GitLabConfig:
    """Resolved connection settings for the current CI environment."""

    def __init__(self, base_url: str, project_path: str, token: str) -> None:
        """Store the three values every API call needs."""
        self.base_url = base_url
        self.project_path = project_path
        self.token = token

    @property
    def project_url_encoded(self) -> str:
        """Project path encoded for the /projects/:id URL segment."""
        return url_encoded_project(self.project_path)

    def http_remote_url(self) -> str:
        """Return a credential-free clone/push URL."""
        return f"{self.base_url}/{self.project_path}.git"

    def git_env(self) -> dict[str, str]:
        """Authenticate trusted git subprocesses without URL/argv credentials."""
        basic = base64.b64encode(f"oauth2:{self.token}".encode()).decode()
        return {
            **os.environ,
            "GIT_CONFIG_COUNT": "3",
            "GIT_CONFIG_KEY_0": f"http.{self.base_url}/.extraHeader",
            "GIT_CONFIG_VALUE_0": f"Authorization: Basic {basic}",
            "GIT_CONFIG_KEY_1": "core.hooksPath",
            "GIT_CONFIG_VALUE_1": "/dev/null",
            "GIT_CONFIG_KEY_2": "core.fsmonitor",
            "GIT_CONFIG_VALUE_2": "false",
        }

    def api(self) -> GitLabApi:
        """Build an API client from this configuration."""
        return GitLabApi(self.base_url, self.token)


def _project_url_candidates(environ: dict[str, str]) -> list[str]:
    """Return candidate full repository URLs, most specific first."""
    return [
        environ.get("GL_PROJECT_URL", ""),
        environ.get("CI_PROJECT_URL", ""),
        environ.get("CI_REPO_LINK", ""),
    ]


def resolve_config(
    environ: dict[str, str] | None = None,
) -> GitLabConfig:
    """Resolve base URL, project path, and token from the environment.

    Works in GitLab CI (CI_SERVER_URL / CI_PROJECT_PATH / CI_PROJECT_URL)
    and in Woodpecker pipelines on the GitLab forge (CI_REPO_LINK), or
    with explicit GL_SERVER_URL / GL_PROJECT_PATH / GL_TOKEN variables.
    """
    env = dict(environ if environ is not None else os.environ)
    token = env.get("GL_TOKEN", "")
    if not token:
        message = "GL_TOKEN is not set"
        raise RuntimeError(message)

    base_url = env.get("GL_SERVER_URL", "").rstrip("/")
    project_path = env.get("GL_PROJECT_PATH", "")

    if not base_url or not project_path:
        for candidate in _project_url_candidates(env):
            if not candidate:
                continue
            parsed = urllib.parse.urlparse(candidate)
            if parsed.scheme not in ("http", "https") or not parsed.netloc:
                continue
            base_url = base_url or f"{parsed.scheme}://{parsed.netloc}"
            project_path = project_path or parsed.path.strip("/")
            break

    if not base_url or not project_path:
        message = (
            "cannot resolve GitLab server/project: set GL_SERVER_URL and "
            "GL_PROJECT_PATH (or GL_PROJECT_URL / CI_PROJECT_URL / CI_REPO_LINK)"
        )
        raise RuntimeError(message)

    return GitLabConfig(base_url=base_url, project_path=project_path, token=token)


def resolve_default_branch(
    environ: dict[str, str] | None = None,
    *,
    api: GitLabApi | None = None,
    project_path_encoded: str = "",
) -> str:
    """Determine the repository's default branch name."""
    env = dict(environ if environ is not None else os.environ)
    for var in ("DEFAULT_BRANCH", "CI_DEFAULT_BRANCH", "CI_REPO_DEFAULT_BRANCH"):
        value = env.get(var, "").strip()
        if value:
            return value
    if api and project_path_encoded:
        project = api.request("GET", f"/projects/{project_path_encoded}")
        branch = project.get("default_branch", "")
        if branch:
            return str(branch)
    log.warning("no default branch variable found; assuming main")
    return "main"
