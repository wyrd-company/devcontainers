[Vector](https://vector.dev/) runs under [s6-overlay](https://github.com/just-containers/s6-overlay) as the selected devcontainer user. Add pipelines as `.yaml`, `.toml` or `.json` files in `/etc/vector/conf.d`; Vector's own watcher loads a new file, reloads a changed one and unloads a removed one without a restart, and keeps the running pipelines when a change does not load. Write a file under a temporary name and rename it into place. Check pipelines with `vector-service validate`. Only the service user can write the directory, because a pipeline can run commands as that user.

Reference secrets as `SECRET[environment.NAME]`; environment interpolation stays off, as upstream defaults. The service loads `NAME=value` lines from `/run/openbao/secrets/vector.env` when that file exists, and waits for it when the [OpenBao Agent](https://openbao.org/) Feature renders it. Restart with `sudo /command/s6-svc -r /run/service/vector` after it changes. File checkpoints live in `/var/lib/vector`; mount a volume there to keep them across rebuilds. If the host has run out of inotify instances, set `watchConfigMethod` to `poll`.

When the [Ansible](https://www.ansible.com/) Feature is installed, Vector starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Datadog, Inc. Vector and its logo are trademarks of Datadog, Inc. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Vector icon from [vector-icon.svg](https://github.com/vectordotdev/vector/blob/0ced36015abbb32bc863e582834514c6fadd5a7f/website/static/press/vector-icon.svg).
