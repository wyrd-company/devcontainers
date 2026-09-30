// ---
// relationships:
//   verifies: codex-cli
// ---
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const path = require("node:path");
const parser =
  process.env.SAMPLE_ARGUMENT_PARSER ||
  path.resolve(
    __dirname,
    "../../../src/features/codex-cli/arguments/parse.cjs",
  );
const parse = (value) =>
  spawnSync(process.execPath, [parser, value], { encoding: "utf8" });
const words = (result) => result.stdout.split("\0").slice(0, -1);
test("quoted paths, optional flags, and spaces remain separate arguments", () => {
  const result = parse(
    '--ws-auth signed-bearer-token --ws-shared-secret-file "/run/secrets/sample key" --ws-issuer "sample issuer" --ws-audience sample --ws-max-clock-skew-seconds 20',
  );
  assert.equal(result.status, 0);
  assert.deepEqual(words(result), [
    "--ws-auth",
    "signed-bearer-token",
    "--ws-shared-secret-file",
    "/run/secrets/sample key",
    "--ws-issuer",
    "sample issuer",
    "--ws-audience",
    "sample",
    "--ws-max-clock-skew-seconds",
    "20",
  ]);
});
test("variables and quoted shell substitutions remain literal", () => {
  const result = parse(
    '--ws-issuer "$SAMPLE_NAME" --ws-audience "$(sample-command)"',
  );
  assert.equal(result.status, 0);
  assert.deepEqual(words(result), [
    "--ws-issuer",
    "$SAMPLE_NAME",
    "--ws-audience",
    "$(sample-command)",
  ]);
});
test("shell operators, unquoted substitution, and glob expansion are rejected", () => {
  for (const value of [
    "--ws-issuer sample; sample-command",
    "--ws-issuer $(sample-command)",
    "--ws-token-file /run/secrets/*",
  ]) {
    const result = parse(value);
    assert.notEqual(result.status, 0);
    assert.equal(result.stdout, "");
  }
});
