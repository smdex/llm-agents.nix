"""Tests for the stdlib GitLab API client."""

from __future__ import annotations

import unittest
from typing import Any

from ci.gitlab_api import (
    GitLabApi,
    GitLabApiError,
    resolve_config,
    resolve_default_branch,
    url_encoded_project,
)


class FakeTransport:
    """Records requests and replays canned responses."""

    def __init__(self, responses: list[tuple[int, bytes, dict[str, str]]]) -> None:
        self.responses = list(responses)
        self.calls: list[dict[str, Any]] = []

    def __call__(
        self, url: str, method: str, headers: dict[str, str], body: bytes | None
    ) -> tuple[int, bytes, dict[str, str]]:
        self.calls.append(
            {"url": url, "method": method, "headers": dict(headers), "body": body}
        )
        return self.responses.pop(0)


def api_with(
    responses: list[tuple[int, bytes, dict[str, str]]],
) -> tuple[GitLabApi, FakeTransport]:
    transport = FakeTransport(responses)
    return GitLabApi(
        "https://gitlab.example.com", "sekrit", transport=transport
    ), transport


class GitLabApiTest(unittest.TestCase):
    def test_get_sends_bearer_token_header_not_url(self) -> None:
        api, transport = api_with([(200, b"[]", {})])

        api.request(
            "GET", "/projects/foo%2Fbar/merge_requests", params={"state": "opened"}
        )

        call = transport.calls[0]
        self.assertNotIn("sekrit", call["url"])
        self.assertEqual(
            call["headers"]["Authorization"],
            "Bearer sekrit",
        )
        self.assertIn("state=opened", call["url"])
        self.assertIn("/api/v4/projects/foo%2Fbar/merge_requests", call["url"])

    def test_post_encodes_json_body(self) -> None:
        api, transport = api_with([(201, b'{"iid": 7}', {})])

        result = api.request(
            "POST",
            "/projects/1/merge_requests",
            json_body={"title": "t"},
        )

        self.assertEqual(result, {"iid": 7})
        call = transport.calls[0]
        self.assertEqual(call["method"], "POST")
        self.assertEqual(call["headers"]["Content-Type"], "application/json")
        self.assertIn(b'"title"', call["body"] or b"")

    def test_error_raises_without_leaking_token(self) -> None:
        api, _transport = api_with([(500, b"boom", {})])

        with self.assertRaises(GitLabApiError) as ctx:
            api.request("GET", "/projects/1")
        message = str(ctx.exception)
        self.assertIn("HTTP 500", message)
        self.assertNotIn("sekrit", message)

    def test_paginate_follows_next_page(self) -> None:
        api, transport = api_with(
            [
                (200, b'[{"iid": 1}]', {"x-next-page": "2"}),
                (200, b'[{"iid": 2}]', {"x-next-page": ""}),
            ]
        )

        items = list(api.paginate("/projects/1/merge_requests"))

        self.assertEqual([item["iid"] for item in items], [1, 2])
        self.assertEqual(len(transport.calls), 2)
        self.assertIn("page=2", transport.calls[1]["url"])

    def test_url_encoded_project(self) -> None:
        self.assertEqual(url_encoded_project("group/sub/repo"), "group%2Fsub%2Frepo")


class ResolveConfigTest(unittest.TestCase):
    def test_explicit_variables(self) -> None:
        config = resolve_config(
            {
                "GL_SERVER_URL": "https://gl.example.com/",
                "GL_PROJECT_PATH": "group/repo",
                "GL_TOKEN": "t0k",
            }
        )
        self.assertEqual(config.base_url, "https://gl.example.com")
        self.assertEqual(config.project_path, "group/repo")
        self.assertEqual(config.project_url_encoded, "group%2Frepo")
        self.assertEqual(
            config.http_remote_url(),
            "https://gl.example.com/group/repo.git",
        )

    def test_git_auth_does_not_embed_token_in_remote(self) -> None:
        config = resolve_config(
            {
                "GL_SERVER_URL": "https://gl.example.com",
                "GL_PROJECT_PATH": "group/repo",
                "GL_TOKEN": "t0k",
            }
        )
        self.assertNotIn("t0k", config.http_remote_url())
        env = config.git_env()
        self.assertEqual(
            env["GIT_CONFIG_KEY_0"], "http.https://gl.example.com/.extraHeader"
        )
        self.assertTrue(env["GIT_CONFIG_VALUE_0"].startswith("Authorization: Basic "))

    def test_falls_back_to_gitlab_ci_url(self) -> None:
        config = resolve_config(
            {
                "CI_PROJECT_URL": "https://gitlab.com/nested/group/repo",
                "GL_TOKEN": "t",
            }
        )
        self.assertEqual(config.base_url, "https://gitlab.com")
        self.assertEqual(config.project_path, "nested/group/repo")

    def test_falls_back_to_woodpecker_repo_link(self) -> None:
        config = resolve_config(
            {
                "CI_REPO_LINK": "https://gitlab.example.com/fork/llm-agents.nix",
                "GL_TOKEN": "t",
            }
        )
        self.assertEqual(config.project_path, "fork/llm-agents.nix")

    def test_missing_token_raises(self) -> None:
        with self.assertRaises(RuntimeError):
            resolve_config({"CI_PROJECT_URL": "https://gitlab.com/a/b"})

    def test_missing_project_raises(self) -> None:
        with self.assertRaises(RuntimeError):
            resolve_config({"GL_SERVER_URL": "https://gl.example.com", "GL_TOKEN": "t"})


class ResolveDefaultBranchTest(unittest.TestCase):
    def test_env_variable_chain(self) -> None:
        self.assertEqual(
            resolve_default_branch({"CI_DEFAULT_BRANCH": "trunk"}), "trunk"
        )
        self.assertEqual(
            resolve_default_branch({"CI_REPO_DEFAULT_BRANCH": "main"}), "main"
        )

    def test_api_fallback(self) -> None:
        api, _transport = api_with([(200, b'{"default_branch": "trunk"}', {})])
        branch = resolve_default_branch(
            {},
            api=api,
            project_path_encoded="a%2Fb",
        )
        self.assertEqual(branch, "trunk")

    def test_defaults_to_main(self) -> None:
        self.assertEqual(resolve_default_branch({}), "main")


if __name__ == "__main__":
    unittest.main()
