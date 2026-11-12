# Vector

Installs [Vector](https://vector.dev/) from the official GitHub release, verified against the release's SHA-256 checksums, and supervises it with [s6-overlay](https://github.com/just-containers/s6-overlay). Vector reads pipelines from a well-known directory and watches it: adding a file loads its pipeline, changing it reloads it, and removing it unloads it, all without restarting Vector.

The Feature requires a Debian/Ubuntu image with s6-overlay 3 already installed.

## Well-known locations

| Purpose                | Location                                 |
| ---------------------- | ---------------------------------------- |
| Pipelines              | `/etc/vector/conf.d/*.yaml`              |
| Managed configuration  | `/etc/vector/vector.yaml`                |
| Data and checkpoints   | `/var/lib/vector`                        |
| Launcher and validator | `/usr/local/bin/vector-service`          |
| Secret backend         | `/usr/local/bin/vector-secret-environment` |
| Secret file            | `/run/openbao/secrets/vector.env`        |

A pipeline file holds any `sources`, `transforms` and `sinks`, in YAML (`.yaml`, `.yml`), TOML (`.toml`) or JSON (`.json`). Vector merges every file in the directory with the managed configuration into one topology, so component ids must be unique across files: prefix them with the file's name. Files with other extensions are ignored.

The service runs `vector --config /etc/vector/vector.yaml --config-dir /etc/vector/conf.d --watch-config --allow-empty-config`, so Vector starts with no pipelines and uses its own configuration watcher. When a changed file does not load, Vector logs `reload aborted` and keeps running the previous pipelines. Until that file is fixed or removed, no other change is applied either.

Write a file under a name Vector ignores, then rename it into place, so that Vector never loads a half-written pipeline:

```bash
cat >/etc/vector/conf.d/.board.yaml.tmp <<'EOF'
...
EOF
mv /etc/vector/conf.d/.board.yaml.tmp /etc/vector/conf.d/board.yaml
```

Check the pipelines before or after a change with `vector-service validate`. It validates the managed configuration and every pipeline file, resolves secrets as the service does, and does not bind ports. Pass extra `vector validate` flags after it, such as `--deny-warnings`. Validation needs at least one source and one sink in the directory.

Vector's own log, including reloads and pipeline errors, goes to the container log. With the API enabled, `vector top` shows the running components and `vector tap` samples the events they emit.

## Who can change pipelines

A pipeline can run commands, for example with the `exec` source, as the user Vector runs as. Only that user (and root) can write `/etc/vector/conf.d`. There is no separate option for the user who manages pipelines: give that user the service by setting `serviceUser`.

## Example: act on kanban-md board activity

[kanban-md](https://github.com/antopolskiy/kanban-md) appends one JSON line per board change to `kanban/activity.jsonl`. This pipeline sends each line to a [Dagu](https://dagu.sh/) webhook, which starts the DAG `board-activity` with the line as its `WEBHOOK_PAYLOAD`. Any other HTTP endpoint, such as a T3 Code webhook, works the same way with a different `uri` and body.

```yaml
# /etc/vector/conf.d/board-activity.yaml
sources:
  board_activity_log:
    type: file
    include:
      - /workspaces/sample-project/kanban/activity.jsonl
transforms:
  board_activity_payload:
    type: remap
    inputs: [board_activity_log]
    source: |
      . = {"payload": parse_json!(string!(.message))}
sinks:
  board_activity_dagu:
    type: http
    inputs: [board_activity_payload]
    uri: http://127.0.0.1:8080/api/v1/webhooks/board-activity
    auth:
      strategy: bearer
      token: "SECRET[environment.DAGU_WEBHOOK_TOKEN]"
    encoding:
      codec: json
    framing:
      method: newline_delimited
    request:
      headers:
        Content-Type: application/json
    batch:
      max_events: 1
```

`batch.max_events: 1` sends one request, and so one DAG run, per line. The file source keeps its read position in `/var/lib/vector`. When the pipeline file is removed and added again later, Vector sends the lines written in between. Vector retries failed requests with a server error or a rate limit, and drops a request that the endpoint rejects with any other client error.

## Secrets

Since Vector 0.58, Vector does not substitute `${NAME}` environment variables in configuration unless it is started with `--dangerously-allow-env-var-interpolation`. This Feature keeps that default. The managed configuration declares an `exec` secret backend named `environment` instead: `SECRET[environment.NAME]` in a pipeline reads the variable `NAME` from Vector's environment. Do not write a `SECRET[...]` placeholder in a comment: Vector resolves placeholders anywhere in a file, and a missing variable stops the file from loading.

The service loads `NAME=value` lines from `/run/openbao/secrets/vector.env` into its environment when that file exists, and waits for it when the [OpenBao Agent](https://openbao.org/) Feature renders it. Values are literal text, not shell, and the container environment takes precedence. A malformed line, or a line that sets one of the `VECTOR_*` variables the Feature manages (see [Environment and flags](#environment-and-flags)), stops the service. Add one Agent `template` whose `destination` is that path:

```hcl
template {
  destination = "/run/openbao/secrets/vector.env"
  perms       = "0640"
  contents    = <<-EOT
    {{ with secret "secret/data/sample-application" -}}
    DAGU_WEBHOOK_TOKEN={{ .Data.data.token }}
    {{- end }}
  EOT
}
```

The environment is read when Vector starts. After the secret file changes, restart the service with `sudo /command/s6-svc -r /run/service/vector`.

## Configuration watcher

On Linux, Vector watches its configuration with inotify. The kernel limits inotify instances per user ID across the whole host (`fs.inotify.max_user_instances`, often 128), so a host that runs many containers as the same user ID can run out. Vector then logs `Unable to start config watcher. error=Too many open files` and exits, and s6 restarts it. Raise the host limit, or set `watchConfigMethod` to `poll`, which checks the configuration every `watchConfigPollIntervalSeconds`.

## Options

| Option                           | Type   | Default          | Description                                                                                            |
| -------------------------------- | ------ | ---------------- | ------------------------------------------------------------------------------------------------------ |
| `version`                        | string | `latest`         | Vector release version, such as `0.61.0`.                                                              |
| `serviceUser`                    | string | `automatic`      | User that runs Vector and owns the pipeline directory. Automatic selection prefers the remote user.   |
| `apiAddress`                     | string | `127.0.0.1:8686` | IPv4 or bracketed IPv6 address and port of the Vector API for `vector top` and `vector tap`. `localhost` becomes `127.0.0.1`. Empty disables the API. |
| `watchConfigMethod`              | string | `recommended`    | `recommended` (inotify) or `poll`.                                                                     |
| `watchConfigPollIntervalSeconds` | string | `30`             | Seconds between configuration checks when `watchConfigMethod` is `poll`.                              |

## Example

```json
{
  "image": "ghcr.io/wyrd-company/devcontainers/base:noble",
  "features": {
    "ghcr.io/wyrd-company/devcontainers/vector:1": {}
  }
}
```

## Environment and flags

Vector runs as the selected user with `HOME` and `USER` set and the rest of the container environment, so pipelines can read the user's files and run the user's tools. The launcher passes the configuration paths and watcher settings as flags, and removes the `VECTOR_CONFIG*`, `VECTOR_WATCH_CONFIG*` and `VECTOR_ALLOW_EMPTY_CONFIG` variables, which would otherwise add configuration files or change the watcher. Other `VECTOR_*` variables, such as `VECTOR_LOG`, still apply.

## Persistence

`/var/lib/vector` holds the file source checkpoints and disk buffers. It survives a container restart, but not a rebuild. Without it, a file source starts again from its `read_from` setting. To keep it across rebuilds, mount a volume:

```json
"mounts": [
  "source=vector-data-${devcontainerId},target=/var/lib/vector,type=volume"
]
```

To keep pipelines with a project, bind-mount a directory over `/etc/vector/conf.d`. It must be writable only by the service user.

## Ansible

When the [Ansible](https://www.ansible.com/) Feature is installed, the `vector` service starts only after the `ansible-setup` s6-rc oneshot finishes. If the oneshot fails, the `vector` service does not start. This Feature declares `installsAfter` for the Ansible Feature, so that the `ansible-setup` service definition exists when this installer runs. The installer adds the dependency only when that definition exists. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Datadog, Inc. Vector and its logo are trademarks of Datadog, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Vector icon from [vector-icon.svg](https://github.com/vectordotdev/vector/blob/0ced36015abbb32bc863e582834514c6fadd5a7f/website/static/press/vector-icon.svg).
