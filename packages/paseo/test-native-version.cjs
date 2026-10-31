// Run with: node packages/paseo/test-native-version.cjs
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const { join } = require("node:path");
const [, pattern] = readFileSync(join(__dirname, "package.nix"), "utf8").match(
  /pkg\.version\.replace\(\/(.+)\/, ""\)/,
);
for (const version of [
  "0.14.0-beta.1",
  "0.14.0-beta.1-smdex",
  "0.14.0-beta.1-smdex.2",
]) {
  assert.equal(version.replace(new RegExp(pattern), ""), "0.14.0-beta.1");
}
