#!/usr/bin/env node
// relationships:
//   verifies: t3code-server
// A valid preflight followed by a failed trial proves native database rollback.
const { DatabaseSync } = require("node:sqlite");
const { writeFileSync } = require("node:fs");
const { join } = require("node:path");

if (process.argv[2] === "__service-preflight") {
  console.log(
    JSON.stringify({
      status: "ready",
      version: "0.1.3-sample.0",
      launcherProtocol: 3,
    }),
  );
} else {
  const db = new DatabaseSync(
    join(process.env.T3CODE_HOME, "userdata", "statev2.sqlite"),
  );
  db.exec("UPDATE sample_restore SET value = 2");
  db.close();
  writeFileSync(
    join(process.env.T3CODE_HOME, "sample-trial-started"),
    "started",
  );
  process.exitCode = 1;
}
