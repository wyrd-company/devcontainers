#!/usr/bin/env python3
"""Unix-socket forward_auth server that runs registered header-helper commands.

Each route is a JSON file `<config-dir>/<route>.json`:

    {
      "command": ["/usr/local/bin/example-headers"],
      "env": {"OPTIONAL": "value"},
      "timeout": 10
    }

On `GET /<route>`, the server runs `command` without a shell, parses its stdout
as a non-empty JSON object of `{HeaderName: value}` pairs, validates each name
and value, and returns `200 OK` with those headers for Caddy's `forward_auth`.
Secrets are never logged or cached.
"""

import argparse
import http.server
import json
import os
from pathlib import Path
import re
import signal
import socketserver
import stat
import subprocess
import sys
import threading
from urllib.parse import urlsplit

ROUTE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
HEADER_NAME_RE = re.compile(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$")
FORBIDDEN_HEADERS = frozenset({
    "connection",
    "content-length",
    "host",
    "keep-alive",
    "proxy-authenticate",
    "proxy-authorization",
    "te",
    "trailer",
    "trailers",
    "transfer-encoding",
    "upgrade",
})
MAX_TIMEOUT = 300.0


def log_error(message: str) -> None:
    sys.stderr.write(f"[caddy-header-auth] {message}\n")
    sys.stderr.flush()


def parse_route_name(raw_path: str) -> str | None:
    path = urlsplit(raw_path).path
    if not path.startswith("/"):
        return None
    name = path[1:]
    if not name or "/" in name or not ROUTE_RE.fullmatch(name):
        return None
    return name


def load_route(config_dir: Path, route_name: str, default_timeout: float) -> tuple[list[str], dict[str, str], float] | None:
    root = config_dir.resolve()
    candidate = config_dir / f"{route_name}.json"
    if not candidate.exists():
        return None

    resolved = candidate.resolve()
    try:
        resolved.relative_to(root)
    except ValueError as err:
        raise ValueError(f"route {route_name!r} escapes config directory") from err

    st = resolved.stat()
    if not stat.S_ISREG(st.st_mode):
        raise ValueError(f"route {route_name!r} is not a regular file")

    data = json.loads(resolved.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("route config must be a JSON object")

    command = data.get("command")
    if (
        not isinstance(command, list)
        or not command
        or not all(isinstance(arg, str) and arg != "" for arg in command)
        or not command[0].startswith("/")
    ):
        raise ValueError("route command must be a non-empty list starting with an absolute path")

    extra_env = data.get("env", {})
    if not isinstance(extra_env, dict) or not all(
        isinstance(k, str) and isinstance(v, str) and k != "" and "\x00" not in k and "\x00" not in v
        for k, v in extra_env.items()
    ):
        raise ValueError("route env must be an object of string pairs")

    timeout = data.get("timeout", default_timeout)
    if isinstance(timeout, bool) or not isinstance(timeout, (int, float)) or timeout <= 0 or timeout > MAX_TIMEOUT:
        raise ValueError(f"route timeout must be between 0 and {int(MAX_TIMEOUT)}")

    env = dict(os.environ)
    env.update(extra_env)
    return command, env, float(timeout)


def validate_headers(raw_stdout: str) -> list[tuple[str, str]]:
    parsed = json.loads(raw_stdout)
    if not isinstance(parsed, dict) or not parsed:
        raise ValueError("helper must output a non-empty JSON object")

    headers: list[tuple[str, str]] = []
    for name, value in parsed.items():
        if not isinstance(name, str) or not HEADER_NAME_RE.fullmatch(name):
            raise ValueError("helper output contains an invalid header name")
        if name.lower() in FORBIDDEN_HEADERS:
            raise ValueError(f"helper output contains forbidden header {name!r}")
        if not isinstance(value, str) or "\r" in value or "\n" in value or "\x00" in value:
            raise ValueError(f"helper output contains an invalid value for header {name!r}")
        headers.append((name, value))
    return headers


class ThreadingUnixHTTPServer(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, socket_path: str, config_dir: Path, default_timeout: float):
        self.config_dir = config_dir
        self.default_timeout = default_timeout
        super().__init__(socket_path, AuthRequestHandler)


class AuthRequestHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server: ThreadingUnixHTTPServer

    def address_string(self) -> str:
        return "unix"

    def log_message(self, format: str, *args) -> None:  # noqa: A002
        return

    def _send_empty(self, status: int, headers: list[tuple[str, str]] | None = None) -> None:
        self.send_response(status)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", "0")
        for name, value in headers or []:
            self.send_header(name, value)
        self.end_headers()

    def _handle_auth(self) -> None:
        route_name = parse_route_name(self.path)
        if route_name is None:
            self._send_empty(404)
            return

        try:
            route = load_route(self.server.config_dir, route_name, self.server.default_timeout)
        except (OSError, ValueError, json.JSONDecodeError) as err:
            log_error(f"invalid route {route_name}: {err}")
            self._send_empty(502)
            return

        if route is None:
            self._send_empty(404)
            return

        command, env, timeout = route
        try:
            result = subprocess.run(
                command,
                env=env,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
        except subprocess.TimeoutExpired:
            log_error(f"route {route_name}: helper timed out after {timeout:g}s")
            self._send_empty(504)
            return
        except OSError as err:
            log_error(f"route {route_name}: failed to run helper ({err.strerror or err})")
            self._send_empty(502)
            return

        if result.returncode != 0:
            log_error(f"route {route_name}: helper exited with status {result.returncode}")
            self._send_empty(502)
            return

        try:
            headers = validate_headers(result.stdout)
        except (ValueError, json.JSONDecodeError) as err:
            log_error(f"route {route_name}: {err}")
            self._send_empty(502)
            return

        self._send_empty(200, headers)

    def do_GET(self) -> None:  # noqa: N802
        self._handle_auth()

    def do_HEAD(self) -> None:  # noqa: N802
        self._handle_auth()

    def do_POST(self) -> None:  # noqa: N802
        self._send_empty(405, [("Allow", "GET, HEAD")])

    def do_PUT(self) -> None:  # noqa: N802
        self._send_empty(405, [("Allow", "GET, HEAD")])

    def do_DELETE(self) -> None:  # noqa: N802
        self._send_empty(405, [("Allow", "GET, HEAD")])

    def do_PATCH(self) -> None:  # noqa: N802
        self._send_empty(405, [("Allow", "GET, HEAD")])


def remove_stale_socket(socket_path: Path) -> None:
    try:
        st = socket_path.lstat()
    except FileNotFoundError:
        return
    if not stat.S_ISSOCK(st.st_mode):
        raise RuntimeError(f"refusing to replace non-socket path: {socket_path}")
    socket_path.unlink()


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Unix-socket forward_auth header-helper server.")
    parser.add_argument("--socket", required=True, help="Path to the Unix domain socket.")
    parser.add_argument("--config-dir", required=True, help="Directory holding <route>.json files.")
    parser.add_argument("--timeout", type=float, default=10.0, help="Default helper timeout in seconds.")
    args = parser.parse_args(argv)
    if args.timeout <= 0 or args.timeout > MAX_TIMEOUT:
        parser.error(f"--timeout must be between 0 and {int(MAX_TIMEOUT)}")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    socket_path = Path(args.socket)
    config_dir = Path(args.config_dir)

    remove_stale_socket(socket_path)
    old_umask = os.umask(0o117)
    try:
        server = ThreadingUnixHTTPServer(str(socket_path), config_dir, args.timeout)
    finally:
        os.umask(old_umask)

    def handle_signal(signum: int, _frame) -> None:
        threading.Thread(target=server.shutdown, daemon=True).start()

    signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)

    try:
        server.serve_forever()
    finally:
        server.server_close()
        try:
            remove_stale_socket(socket_path)
        except OSError:
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
