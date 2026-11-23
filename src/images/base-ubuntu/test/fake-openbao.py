#!/usr/bin/env python3
"""Serve a fake OpenBao KV version 2 API on a Unix socket, as the Wyrwood vault.sock does.

Usage: fake-openbao.py SOCKET LOG

It answers GET /v1/secret/data/sample-app, refuses secret/data/sample-denied
with 403, returns a non-KV body for secret/data/sample-not-kv, and 404 for
anything else. Each request line, and whether it carried a token header, is
appended to LOG.
"""

import http.server
import json
import os
import socketserver
import sys

SECRETS = {
    "/v1/secret/data/sample-app": {
        "token": "sample-token-value",
        "port": 8080,
        "enabled": True,
        "nested": {"sample": "value"},
    },
    "/v1/kv/data/sample-team/sample-service": {"password": "sample-password-value"},
}


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        token = "token" if self.headers.get("X-Vault-Token") else "no-token"
        with open(LOG, "a", encoding="utf-8") as log:
            log.write(f"GET {self.path} {token}\n")
        if self.path in SECRETS:
            self.reply(200, {"data": {"data": SECRETS[self.path], "metadata": {"version": 1}}})
        elif self.path == "/v1/secret/data/sample-denied":
            self.reply(403, {"errors": ["permission denied"]})
        elif self.path == "/v1/secret/data/sample-not-kv":
            self.reply(200, ["sample", "not", "kv"])
        else:
            self.reply(404, {"errors": []})

    def reply(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


class Server(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True


SOCKET, LOG = sys.argv[1], sys.argv[2]
with Server(SOCKET, Handler) as server:
    os.chmod(SOCKET, 0o666)
    server.serve_forever()
