// ---
// relationships:
//   verifies: codex-cli
// ---
import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import WebSocket from "ws";
const endpoint = process.env.SAMPLE_EXEC_ENDPOINT || "ws://127.0.0.1:4501";
const mode = process.env.SAMPLE_EXEC_AUTH || "capability";
const ca = process.env.SAMPLE_CA_FILE
  ? fs.readFileSync(process.env.SAMPLE_CA_FILE)
  : undefined;
const sockets = [];
const options = (token) => ({
  ca,
  ...(token ? { headers: { Authorization: "Bearer " + token } } : {}),
});
const encode = (value) =>
  Buffer.from(JSON.stringify(value)).toString("base64url");
const jwt = (audience) => {
  const data =
    encode({ alg: "HS256", typ: "JWT" }) +
    "." +
    encode({
      sub: "sample-client",
      iss: "sample issuer",
      aud: audience,
      exp: Math.floor(Date.now() / 1000) + 90,
    });
  return (
    data +
    "." +
    crypto
      .createHmac("sha256", "sample-shared-secret-for-integration-tests")
      .update(data)
      .digest("base64url")
  );
};
async function rejected(token) {
  const socket = new WebSocket(endpoint, options(token));
  sockets.push(socket);
  const status = await new Promise((resolve, reject) => {
    socket.once("unexpected-response", (_request, response) => {
      resolve(response.statusCode);
      response.resume();
      socket.terminate();
    });
    socket.once("open", () =>
      reject(new Error("Unauthenticated exec connection was accepted")),
    );
    socket.once("error", () => {});
  });
  assert.equal(status, 401);
}
try {
  if (mode !== "none") {
    await rejected();
    await rejected("sample-incorrect-token");
    if (mode === "signed") await rejected(jwt("sample-wrong-audience"));
  }
  const token =
    mode === "signed"
      ? jwt("sample-audience")
      : mode === "capability"
        ? "sample-capability-token-for-integration"
        : undefined;
  const socket = new WebSocket(endpoint, options(token));
  sockets.push(socket);
  await new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
  const pending = new Map();
  let nextId = 0;
  socket.on("message", (data) => {
    const message = JSON.parse(data);
    const request = pending.get(message.id);
    if (request) {
      pending.delete(message.id);
      message.error
        ? request.reject(new Error(message.error.message))
        : request.resolve(message.result);
    }
  });
  const request = (method, params) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });
  const initialized = await request("initialize", {
    clientName: "sample-probe",
  });
  assert.equal(typeof initialized.sessionId, "string");
  socket.send(JSON.stringify({ method: "initialized", params: {} }));
  const info = await request("environment/info", {});
  assert.ok(info.environmentInfo || info.shell);
  console.log(
    `Exec-server ${mode} authentication and native handshake passed.`,
  );
} finally {
  for (const socket of sockets) socket.terminate();
}
