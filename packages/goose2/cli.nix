# The added desktop/TUI apps need Goose CLI, not its obsolete V8 download.
{ goose-cli }:
goose-cli.overrideAttrs (old: {
  env = builtins.removeAttrs (old.env or { }) [ "RUSTY_V8_ARCHIVE" ];
})
