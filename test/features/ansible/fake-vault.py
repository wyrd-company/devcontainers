#!/usr/bin/env python3
"""Serve a minimal OpenBao health response on a Unix socket, as the Wyrwood vault.sock does."""

import http.server
import os
import socketserver
import sys


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'{"initialized":true,"sealed":false}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass


socket_path = sys.argv[1]
with socketserver.UnixStreamServer(socket_path, Handler) as server:
    os.chmod(socket_path, 0o666)
    server.serve_forever()
