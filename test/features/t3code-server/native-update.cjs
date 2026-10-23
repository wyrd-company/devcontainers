// relationships:
//   verifies: t3code-server
// Runs inside the disposable acceptance container as the service user. Tokens
// are minted for this fixture and stay in memory; no user credentials are read.
const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");

async function main() {
  const targetVersion = process.argv[2];
  const token = execFileSync(
    "/usr/local/bin/t3",
    [
      "auth",
      "session",
      "issue",
      "--token-only",
      "--base-dir",
      "/home/vscode/.t3",
    ],
    { encoding: "utf8" },
  ).trim();
  const response = await fetch(
    "http://127.0.0.1:3773/api/auth/websocket-ticket",
    {
      method: "POST",
      headers: { authorization: `Bearer ${token}` },
    },
  );
  assert.equal(
    response.status,
    200,
    "Could not issue the fixture WebSocket ticket",
  );
  const { ticket } = await response.json();
  const ws = new WebSocket(
    `ws://127.0.0.1:3773/ws?orchestrationProtocol=2&wsTicket=${encodeURIComponent(ticket)}`,
  );
  // Same acceptance window as the shell console probe, including download.
  const deadline = setTimeout(() => {
    throw new Error("Native update RPC did not complete");
  }, 120_000);
  try {
    const result = await new Promise((resolve, reject) => {
      ws.onopen = () =>
        ws.send(
          JSON.stringify({
            _tag: "Request",
            id: "sample-request",
            headers: [],
            tag: targetVersion ? "server.updateServer" : "server.getConfig",
            payload: targetVersion ? { targetVersion } : {},
          }),
        );
      ws.onerror = () => reject(new Error("Fixture WebSocket failed"));
      ws.onclose = () =>
        reject(new Error("Connection closed before the RPC result"));
      ws.onmessage = ({ data }) => {
        const message = JSON.parse(data);
        if (message._tag === "Exit" && message.requestId === "sample-request") {
          if (message.exit._tag === "Success") resolve(message.exit.value);
          else
            reject(
              new Error(`Native RPC rejected: ${JSON.stringify(message.exit)}`),
            );
        }
      };
    });
    if (targetVersion) {
      assert.equal(result.method, "boot-service");
      assert.equal(result.targetVersion, targetVersion);
      assert.ok(result.updateId);
      console.log(`Native update accepted for ${targetVersion}.`);
    } else {
      assert.equal(
        result.environment.capabilities.serverSelfUpdate,
        "boot-service",
      );
      console.log("Server advertises native boot-service updates.");
    }
  } finally {
    clearTimeout(deadline);
    ws.close();
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
