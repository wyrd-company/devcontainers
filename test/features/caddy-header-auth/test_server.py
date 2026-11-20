#!/usr/bin/env python3
"""Unit and integration tests for caddy-header-auth's Unix-socket server."""

import http.client
import http.server
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import sys
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
SERVER_PATH = ROOT / "src/features/caddy-header-auth/server.py"

spec = importlib.util.spec_from_file_location("caddy_header_auth_server", SERVER_PATH)
server_mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server_mod)


class UnixHTTPConnection(http.client.HTTPConnection):
    def __init__(self, socket_path: str, timeout: float = 5.0):
        super().__init__("localhost", timeout=timeout)
        self._socket_path = socket_path

    def connect(self) -> None:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.settimeout(self.timeout)
        sock.connect(self._socket_path)
        self.sock = sock


def unix_request(socket_path: Path, method: str, path: str) -> tuple[int, dict[str, str]]:
    conn = UnixHTTPConnection(str(socket_path))
    try:
        conn.request(method, path)
        resp = conn.getresponse()
        resp.read()
        return resp.status, {k.lower(): v for k, v in resp.getheaders()}
    finally:
        conn.close()


class ServerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="caddy-header-auth-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config_dir = self.root / "conf.d"
        self.config_dir.mkdir(mode=0o755)
        self.socket_path = self.root / "auth.sock"
        self.stderr_log = self.root / "stderr.log"

        self.stderr_handle = open(self.stderr_log, "w", encoding="utf-8")
        self.addCleanup(self.stderr_handle.close)
        self.proc = subprocess.Popen(
            [
                sys.executable,
                str(SERVER_PATH),
                "--socket",
                str(self.socket_path),
                "--config-dir",
                str(self.config_dir),
                "--timeout",
                "2",
            ],
            stdout=subprocess.DEVNULL,
            stderr=self.stderr_handle,
        )
        self.addCleanup(self._stop_server)

        for _ in range(100):
            if self.socket_path.exists():
                break
            time.sleep(0.05)
        self.assertTrue(self.socket_path.exists(), "server did not create Unix socket")

    def _stop_server(self) -> None:
        if self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)

    def write_helper(self, name: str, script: str) -> Path:
        path = self.root / name
        path.write_text(script, encoding="utf-8")
        path.chmod(0o755)
        return path

    def write_route(self, name: str, payload: dict) -> Path:
        path = self.config_dir / f"{name}.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_socket_mode_is_group_accessible_only(self) -> None:
        mode = stat.S_IMODE(self.socket_path.stat().st_mode)
        self.assertEqual(mode & 0o007, 0)
        self.assertEqual(mode & 0o660, 0o660)

    def test_valid_route_and_hot_reload_without_restart(self) -> None:
        status, _ = unix_request(self.socket_path, "GET", "/sample-mcp")
        self.assertEqual(status, 404)

        helper = self.write_helper(
            "sample-helper.sh",
            '#!/bin/sh\nprintf \'{"Authorization":"Bearer %s","X-Custom":"ok"}\' "$SAMPLE_TOKEN"\n',
        )
        route = self.write_route(
            "sample-mcp",
            {"command": [str(helper)], "env": {"SAMPLE_TOKEN": "sample-secret-1"}},
        )

        status, headers = unix_request(self.socket_path, "GET", "/sample-mcp")
        self.assertEqual(status, 200)
        self.assertEqual(headers["authorization"], "Bearer sample-secret-1")
        self.assertEqual(headers["x-custom"], "ok")
        self.assertEqual(headers["cache-control"], "no-store")

        # Update route on disk without restarting server.
        self.write_route(
            "sample-mcp",
            {"command": [str(helper)], "env": {"SAMPLE_TOKEN": "sample-secret-2"}},
        )
        status, headers = unix_request(self.socket_path, "GET", "/sample-mcp")
        self.assertEqual(status, 200)
        self.assertEqual(headers["authorization"], "Bearer sample-secret-2")

        # Remove route on disk without restarting server.
        route.unlink()
        status, _ = unix_request(self.socket_path, "GET", "/sample-mcp")
        self.assertEqual(status, 404)

    def test_rejects_bad_methods_and_path_traversal(self) -> None:
        status, headers = unix_request(self.socket_path, "POST", "/sample")
        self.assertEqual(status, 405)
        self.assertEqual(headers["allow"], "GET, HEAD")

        for bad_path in ("/", "/../outside", "/.hidden", "/a/b", "/bad%2Fname"):
            with self.subTest(bad_path=bad_path):
                status, _ = unix_request(self.socket_path, "GET", bad_path)
                self.assertEqual(status, 404)

        outside = self.root / "outside.json"
        outside.write_text(json.dumps({"command": ["/bin/true"]}), encoding="utf-8")
        (self.config_dir / "escape.json").symlink_to(outside)
        status, _ = unix_request(self.socket_path, "GET", "/escape")
        self.assertEqual(status, 502)

    def test_fails_closed_on_helper_errors_and_never_logs_secrets(self) -> None:
        cases = [
            ("nonzero", '#!/bin/sh\necho "LEAKED_STDERR" >&2\necho "LEAKED_STDOUT"\nexit 1\n', 502),
            ("empty-json", '#!/bin/sh\nprintf "{}"\n', 502),
            ("not-json", '#!/bin/sh\nprintf "LEAKED_RAW_TOKEN"\n', 502),
            ("crlf", '#!/bin/sh\nprintf \'{"Authorization":"Bearer ok\\r\\nX-Injected: yes"}\'\n', 502),
            ("forbidden-header", '#!/bin/sh\nprintf \'{"Content-Length":"99"}\'\n', 502),
            ("timeout", '#!/bin/sh\nsleep 5\n', 504),
        ]
        for name, script, expected in cases:
            with self.subTest(case=name):
                helper = self.write_helper(f"{name}.sh", script)
                route_cfg = {"command": [str(helper)]}
                if name == "timeout":
                    route_cfg["timeout"] = 0.2
                self.write_route(name, route_cfg)
                status, _ = unix_request(self.socket_path, "GET", f"/{name}")
                self.assertEqual(status, expected)

        stderr_text = self.stderr_log.read_text(encoding="utf-8")
        self.assertNotIn("LEAKED_STDERR", stderr_text)
        self.assertNotIn("LEAKED_STDOUT", stderr_text)
        self.assertNotIn("LEAKED_RAW_TOKEN", stderr_text)

    def test_rejects_relative_command_path(self) -> None:
        self.write_route("relative", {"command": ["sh", "-c", "true"]})
        status, _ = unix_request(self.socket_path, "GET", "/relative")
        self.assertEqual(status, 502)

    @unittest.skipUnless(shutil.which("caddy"), "caddy binary not installed")
    def test_end_to_end_with_caddy_forward_auth(self) -> None:
        helper = self.write_helper(
            "xolotl-helper.sh",
            '#!/bin/sh\nprintf \'{"Authorization":"Bearer sample-mcp-token"}\'\n',
        )
        self.write_route("sample-mcp", {"command": [str(helper)]})

        received = []

        class Upstream(http.server.BaseHTTPRequestHandler):
            def do_POST(self):  # noqa: N802
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length).decode("utf-8")
                received.append({
                    "path": self.path,
                    "auth": self.headers.get("Authorization"),
                    "body": body,
                })
                payload = json.dumps({"ok": True}).encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, format, *args):  # noqa: A002
                return

        upstream = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        self.addCleanup(upstream.shutdown)
        self.addCleanup(upstream.server_close)
        threading.Thread(target=upstream.serve_forever, daemon=True).start()
        upstream_port = upstream.server_address[1]

        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            caddy_port = sock.getsockname()[1]

        caddyfile = self.root / "Caddyfile"
        caddyfile.write_text(
            f"""{{
    admin off
    auto_https off
}}

http://127.0.0.1:{caddy_port} {{
    bind 127.0.0.1

    handle /mcp {{
        forward_auth unix/{self.socket_path} {{
            uri /sample-mcp
            copy_headers Authorization
        }}

        reverse_proxy http://127.0.0.1:{upstream_port} {{
            flush_interval -1
        }}
    }}

    handle {{
        respond 404
    }}
}}
""",
            encoding="utf-8",
        )

        caddy = subprocess.Popen(
            ["caddy", "run", "--config", str(caddyfile), "--adapter", "caddyfile"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        self.addCleanup(lambda: (caddy.terminate(), caddy.wait(timeout=5)))

        for _ in range(60):
            try:
                conn = http.client.HTTPConnection("127.0.0.1", caddy_port, timeout=1)
                conn.request("GET", "/other")
                resp = conn.getresponse()
                resp.read()
                conn.close()
                if resp.status == 404:
                    break
            except OSError:
                time.sleep(0.1)

        conn = http.client.HTTPConnection("127.0.0.1", caddy_port, timeout=5)
        try:
            conn.request(
                "POST",
                "/mcp",
                body='{"jsonrpc":"2.0","id":1,"method":"initialize"}',
                headers={
                    "Content-Type": "application/json",
                    "Authorization": "Bearer spoofed",
                },
            )
            resp = conn.getresponse()
            body = resp.read().decode("utf-8")
            self.assertEqual(resp.status, 200)
            self.assertEqual(json.loads(body), {"ok": True})
        finally:
            conn.close()

        self.assertEqual(len(received), 1)
        self.assertEqual(received[0]["path"], "/mcp")
        self.assertEqual(received[0]["auth"], "Bearer sample-mcp-token")
        self.assertEqual(received[0]["body"], '{"jsonrpc":"2.0","id":1,"method":"initialize"}')


if __name__ == "__main__":
    unittest.main()
