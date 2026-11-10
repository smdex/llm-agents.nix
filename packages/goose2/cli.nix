# Keep the added desktop/TUI apps' verified ACP backend private; public goose-cli follows upstream.
{ goose-cli, fetchFromGitHub }:
goose-cli.overrideAttrs (
  finalAttrs: old: {
    version = "1.57.0";
    src = fetchFromGitHub {
      owner = "aaif-goose";
      repo = "goose";
      tag = "v${finalAttrs.version}";
      hash = "sha256-hFW9gcuYFyyXOU/tB2v5WVNlX9arMG0Qs5qMb+KRmqw=";
    };
    cargoHash = "sha256-jVgT8mYFX0KHjcpmK6TbshElXkLpNKgZoZz1JXXi0mk=";
    env = builtins.removeAttrs (old.env or { }) [ "RUSTY_V8_ARCHIVE" ];
  }
)
