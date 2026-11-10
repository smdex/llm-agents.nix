"""Forge automation scripts shared by GitLab CI and Woodpecker pipelines.

The scripts here mirror the upstream GitHub workflows
(`.github/workflows/sync-upstream.yml`, `update-fork.yml`, `auto-merge.yml`)
without modifying them: the updater entry points under `.github/ci/` are
reused verbatim as subprocesses, and this package only adds branch
bookkeeping, credential isolation, and GitLab MR publishing.
"""
