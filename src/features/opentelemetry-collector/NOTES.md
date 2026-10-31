The [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/) runs under [s6-overlay](https://github.com/just-containers/s6-overlay) as the selected devcontainer user. The starter configuration accepts OTLP gRPC on `127.0.0.1:4317`, OTLP HTTP on `127.0.0.1:4318`, and exposes health on `127.0.0.1:13133`. Bind-mount project configuration over `/etc/opentelemetry-collector/config.yaml` when needed. A user with sudo access can restart the service with `sudo /command/s6-svc -r /run/service/opentelemetry-collector`. The service loads `NAME=value` lines from `/run/openbao/secrets/opentelemetry-collector.env` when that file exists, and waits for it when the [OpenBao Agent](https://openbao.org/) Feature renders it.

When the [Ansible](https://www.ansible.com/) Feature is installed, the Collector starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change.

## Trademarks

This feature is not affiliated with or endorsed by The Linux Foundation. OpenTelemetry and its logo are trademarks of The Linux Foundation. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

Logo: the OpenTelemetry icon from [opentelemetry-icon-color.svg](https://github.com/cncf/artwork/blob/b4b5989332c822ef09d5b38a512e2b39c63e32f2/projects/opentelemetry/icon/color/opentelemetry-icon-color.svg).
