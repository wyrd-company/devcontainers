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
| Secret backend         | `/usr/local/bin/bao-secret vector`       |

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
      token: "SECRET[openbao.secret/sample-application/token]"
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

Pipelines read secrets from [OpenBao](https://openbao.org/) while they load. The managed configuration declares an `exec` secret backend named `openbao` that runs `bao-secret vector` from the [Wyrd base image](https://wyrd.foo/tools/base). `SECRET[openbao.<mount>/<path>/<field>]` reads one field of a KV version 2 secret: `SECRET[openbao.secret/sample-application/token]` reads the field `token` of `secret/sample-application`.

- `bao-secret` reads the OpenBao address from `BAO_ADDR`, then `VAULT_ADDR`, in Vector's environment, and sends no token: the address must authenticate the caller, as the [Wyrwood](https://wyrd.foo/tools/wyrwood/) socket `unix:///run/wyrwood/vault.sock` does. See the base image's [Secrets](https://wyrd.foo/docs/base/secrets) page.
- Values stay in Vector's memory. The Feature and `bao-secret` do not write them to a file or put them in an environment variable.
- Vector itself can print a resolved value in its own configuration errors, which go to the container log. With Vector 0.62.0, a secret placed inside a URI that Vector rejects appears in the error message. Put secrets only in fields that hold a whole credential, such as `auth.token`, `auth.password` or a request header, never inside a `uri`, a template or other text that Vector parses.
- Vector reads the secrets each time it loads the pipelines, at start and at every reload. A rotated secret takes effect at the next change to a pipeline file, or after `sudo /command/s6-svc -r /run/service/vector`.
- A secret that is missing or not permitted stops the file that uses it from loading, with the reason in the container log, and Vector keeps running the previous pipelines. `vector-service validate` reports the same error.
- Reference segments hold only letters, digits, `.`, `_` and `-`. Vector does not recognize a placeholder with other characters, such as `#` or `:`, and passes it on as literal text without an error.
- Do not write a `SECRET[...]` placeholder in a comment: Vector resolves placeholders anywhere in a file.

Vector does not substitute `${NAME}` environment variables in configuration unless it is started with `--dangerously-allow-env-var-interpolation`, and this Feature keeps that default.

The Feature requires `/usr/local/bin/bao-secret`. When the image does not have it, the installer logs a warning, and only pipelines that read a secret fail to load.

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

The Dev Container CLI can change the service user's UID and GID when it creates the container, to match the host user (`updateRemoteUserUID`). When the service starts, it gives the entries in `/etc/vector/conf.d` that still have the user's install-time UID or GID to the user's current IDs. Entries of other owners, such as files in a bind-mounted directory, keep theirs. `/var/lib/vector` belongs to Vector alone: at every start, everything in it is given to the service user, including a volume kept from a container that ran with another UID. Symlinks are not followed and other mounts are not entered.

## Ansible

When the [Ansible](https://www.ansible.com/) Feature is installed, the `vector` service starts only after the `ansible-setup` s6-rc oneshot finishes. If the oneshot fails, the `vector` service does not start. This Feature declares `installsAfter` for the Ansible Feature, so that the `ansible-setup` service definition exists when this installer runs. The installer adds the dependency only when that definition exists. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Datadog, Inc. Vector and its logo are trademarks of Datadog, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Vector icon from [vector-icon.svg](https://github.com/vectordotdev/vector/blob/0ced36015abbb32bc863e582834514c6fadd5a7f/website/static/press/vector-icon.svg).
