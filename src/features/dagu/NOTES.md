[Dagu](https://dagu.sh/) runs `start-all` under [s6-overlay](https://github.com/just-containers/s6-overlay) as the selected devcontainer user. Configuration, DAG definitions, logs, and state use Dagu's native per-user paths and are not persisted by this Feature. Add per-container bind mounts when persistence is required. Set `dnsName` with the [Caddy](https://caddyserver.com/) Feature to expose Dagu through HTTPS. The service loads `NAME=value` lines from `/run/openbao/secrets/dagu.env` when that file exists, and waits for it when the [OpenBao Agent](https://openbao.org/) Feature renders it.

When the [Ansible](https://www.ansible.com/) Feature is installed, Dagu starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by Yota Hamada. Dagu and its logo are trademarks of Yota Hamada. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the Dagu mark from [dagu.sh/icon.svg](https://dagu.sh/icon.svg), without its white backdrop. No trademark terms are published.
