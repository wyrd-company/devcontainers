#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
base_image="${BASE_IMAGE:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
image="${1:-devcontainers-caddy-header-auth-runtime:test}"
name="caddy-header-auth-runtime-test-${RANDOM}-$$"

cleanup() {
    docker stop "${name}" >/dev/null 2>&1 || true
    docker rm "${name}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

docker build \
    --file "${repo_root}/test/features/caddy-header-auth/runtime.Dockerfile" \
    --build-arg "BASE_IMAGE=${base_image}" \
    --tag "${image}" \
    "${repo_root}"

"${repo_root}/scripts/check-sudo-no-all.sh" "${image}"

# Verify invalid options are rejected fast at install time.
if docker run --rm --entrypoint bash \
    --volume "${repo_root}/src/features/caddy-header-auth:/feature:ro" \
    --env SERVICEUSER=automatic \
    --env SOCKETGROUP=sample-missing-group \
    --env SOCKETPATH=/run/caddy-header-auth/auth.sock \
    --env CONFIGDIR=/etc/caddy-header-auth/conf.d \
    --env TIMEOUTSECONDS=10 \
    "${image}" /feature/install.sh >/dev/null 2>&1; then
    echo "Expected install to reject a missing socketGroup." >&2
    exit 1
fi

if docker run --rm --entrypoint bash \
    --volume "${repo_root}/src/features/caddy-header-auth:/feature:ro" \
    --env SERVICEUSER=automatic \
    --env SOCKETGROUP=automatic \
    --env SOCKETPATH=relative/auth.sock \
    --env CONFIGDIR=/etc/caddy-header-auth/conf.d \
    --env TIMEOUTSECONDS=10 \
    "${image}" /feature/install.sh >/dev/null 2>&1; then
    echo "Expected install to reject a relative socketPath." >&2
    exit 1
fi

docker run --detach --name "${name}" \
    --env SAMPLE_RUNTIME_VALUE=sample-runtime-value \
    "${image}" >/dev/null

for _ in $(seq 1 30); do
    if docker exec "${name}" test -S /run/caddy-header-auth/auth.sock \
        && docker exec "${name}" test -S /run/caddy/admin.sock; then
        break
    fi
    sleep 0.5
done
docker exec "${name}" test -S /run/caddy-header-auth/auth.sock
docker exec "${name}" test -S /run/caddy/admin.sock

# Verify process ownership, socket permissions, and environment.
test "$(docker exec "${name}" stat -c '%a %U:%G' /run/caddy-header-auth)" = "2750 vscode:caddy"
test "$(docker exec "${name}" stat -c '%a %U:%G' /run/caddy-header-auth/auth.sock)" = "660 vscode:caddy"

pid="$(docker exec "${name}" pgrep -f '/usr/local/lib/caddy-header-auth/server.py' | head -n 1)"
test -n "${pid}"
test "$(docker exec "${name}" ps -o user= -p "${pid}" | tr -d ' ')" = vscode
for expected in HOME=/home/vscode USER=vscode SAMPLE_RUNTIME_VALUE=sample-runtime-value; do
    docker exec --user vscode "${name}" sh -c 'tr "\0" "\n" <"/proc/$1/environ" | grep -Fxq "$2"' sh "${pid}" "${expected}"
done

# Start a mock upstream inside the container and configure a route + Caddy system.d fragment.
docker exec -d "${name}" python3 -c '
import http.server, json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(n).decode()
        out = json.dumps({"auth": self.headers.get("Authorization"), "body": body}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(out)))
        self.end_headers()
        self.wfile.write(out)
    def log_message(self, *args): pass
http.server.ThreadingHTTPServer(("127.0.0.1", 19001), H).serve_forever()
'

docker exec "${name}" bash -c '
cat >/usr/local/bin/sample-headers <<EOF
#!/bin/sh
printf "{\"Authorization\":\"Bearer %s\"}" "\${SAMPLE_RUNTIME_VALUE}"
EOF
chmod 0755 /usr/local/bin/sample-headers
printf "{\"command\":[\"/usr/local/bin/sample-headers\"]}\n" >/etc/caddy-header-auth/conf.d/sample-mcp.json
cat >/etc/caddy/system.d/sample-mcp.caddy <<EOF
http://127.0.0.1:18317 {
    bind 127.0.0.1
    handle /mcp {
        forward_auth unix//run/caddy-header-auth/auth.sock {
            uri /sample-mcp
            copy_headers Authorization
        }
        reverse_proxy http://127.0.0.1:19001 {
            flush_interval -1
        }
    }
    handle {
        respond 404
    }
}
EOF
'

for _ in $(seq 1 30); do
    if docker exec "${name}" curl -fsS -X POST http://127.0.0.1:18317/mcp \
        -H 'Content-Type: application/json' -d '{"ok":true}' >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

resp="$(docker exec "${name}" curl -fsS -X POST http://127.0.0.1:18317/mcp \
    -H 'Content-Type: application/json' -H 'Authorization: Bearer spoofed' -d '{"ok":true}')"
test "$(printf '%s' "${resp}" | jq -r '.auth')" = "Bearer sample-runtime-value"
test "$(printf '%s' "${resp}" | jq -r '.body')" = '{"ok":true}'
test "$(docker exec "${name}" curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1:18317/other)" = "404"

printf 'caddy-header-auth s6 runtime and Caddy forward_auth checks passed.\n'
