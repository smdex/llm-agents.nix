// Run with: node packages/paseo/test-native-version.cjs "$(nix eval --raw .#paseo.src.outPath)"
const assert = require("node:assert/strict");
const { join, resolve } = require("node:path");
assert.ok(process.argv[2], "Pass the realized paseo.src directory");
const { getNativeReleaseVersion } = require(
  join(resolve(process.argv[2]), "packages/app/native-release-version.js"),
);
for (const version of [
  "0.14.0-beta.1",
  "0.14.0-beta.1-smdex",
  "0.14.0-beta.1-smdex.3",
]) {
  assert.deepEqual(getNativeReleaseVersion(version), {
    appVersion: "0.14.0",
    androidVersionCode: 14000,
    iosBuildNumber: "14000001",
  });
}
assert.deepEqual(getNativeReleaseVersion("0.16.0-smdex.5"), {
  appVersion: "0.16.0",
  androidVersionCode: 16000,
  iosBuildNumber: "16000999",
});
assert.throws(() => getNativeReleaseVersion("0.14.0-beta.999"), /beta number/);
assert.throws(() => getNativeReleaseVersion("not-a-version"), /unsupported version/);
