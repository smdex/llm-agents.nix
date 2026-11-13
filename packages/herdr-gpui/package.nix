{ allPackages }:

# Compatibility alias: sheprd was renamed from herdr-gpui. One derivation in
# packages/sheprd; this exposes the old flake attribute for existing users.
# overrideAttrs (not //) so the merged passthru spreads to the derivation's
# top level, where the docs and updater checks read hideFromDocs/skipUpdate.
allPackages.sheprd.overrideAttrs (old: {
  passthru = (old.passthru or { }) // {
    hideFromDocs = true;
    skipUpdate = true;
  };
})
