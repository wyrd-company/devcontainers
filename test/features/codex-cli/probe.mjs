// ---
// relationships:
//   verifies: codex-cli
// ---
import net from "node:net";
import WebSocket from "ws";
const clients = [];
async function connect() {
  const socket = new WebSocket("ws://localhost", {
    createConnection: () =>
      net.createConnection(
        "/home/vscode/.codex/app-server-control/app-server-control.sock",
      ),
  });
  clients.push(socket);
  await new Promise((resolve, reject) => {
    socket.once("open", resolve);
    socket.once("error", reject);
  });
  let nextId = 0;
  const pending = new Map();
  socket.on("message", (data) => {
    const reply = JSON.parse(data.toString());
    const completion = pending.get(reply.id);
    if (!completion) return;
    pending.delete(reply.id);
    if (reply.error) completion.reject(new Error(reply.error.message));
    else completion.resolve(reply.result);
  });
  const request = (method, params) =>
    new Promise((resolve, reject) => {
      const id = nextId++;
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });
  await request("initialize", {
    clientInfo: { name: "sample_probe", version: "1.0.0" },
    capabilities: { experimentalApi: true },
  });
  socket.send(JSON.stringify({ method: "initialized", params: {} }));
  return request;
}
try {
  const a = await connect();
  const b = await connect();
  const status = await a("remoteControl/status/read", {});
  if (status.status !== "disabled")
    throw new Error("Remote control was not disabled by the Feature option");
  const first = await a("thread/start", {
    ephemeral: true,
    cwd: "/tmp",
    approvalPolicy: "never",
    sandbox: "read-only",
  });
  const loaded = await b("thread/loaded/list", {});
  if (!loaded.data.includes(first.thread.id))
    throw new Error("Clients did not share the live thread");
  console.log("Two clients share a live thread on the S6 app-server.");
} finally {
  for (const socket of clients) socket.terminate();
}
