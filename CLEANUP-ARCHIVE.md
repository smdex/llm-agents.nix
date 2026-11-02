# Preserved pre-cleanup customizations

This archive retains the complete pre-cleanup main history. Its parent is
`90cbc830883c60ef9654f55eeccae8c8c6f0500a`. The companion archive branch
`archive/round3-chiki-before-cleanup-20261102` preserves chiki at
`1e238a58ed7ac10a3ad0cc5e64a60dbaa5dbf0f6`.

`cleanup-archive-manifest.json` classifies paths against upstream
`10f2be38f8a46fdf7689697270dd14b27f723aae`; `cleanup-parked.patch` preserves the
non-ctx upstream-owned package and shared updater changes being parked. Apply
that patch only after reviewing its original upstream base. The original
commits remain available through both archive branches; no working-directory
stash was used.

The active cleanup keeps the necessary ctx ZFS patch, intended package additions
except the three requested removals, and explicit chiki fork/cache policy.
Minimal shared dependencies needed by retained added packages are documented in
the cleanup report, not silently treated as upstream-owned release refreshes.
