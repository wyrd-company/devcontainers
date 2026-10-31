[OpenBao Agent](https://openbao.org/) runs under [s6-overlay](https://github.com/just-containers/s6-overlay) as `root` by default; `serviceUser` overrides this. Supply a readable Agent configuration at `/etc/openbao/agent.hcl`, or at `configPath`, and restart the service with `sudo /command/s6-svc -r /run/service/openbao-agent` after changing it. To give a secret to another Feature's service, add a `template` with the destination `/run/openbao/secrets/<feature-id>.env`; the service waits for that file and loads its `NAME=value` lines at start.

When the [Ansible](https://www.ansible.com/) Feature is installed, the `openbao-agent` service starts only after the `ansible-setup` s6-rc oneshot finishes, and does not start if it fails. Without Ansible, startup does not change. The `openbao-secrets` oneshot only creates the secret directory and group. It does not wait, so that other Features can find the directory at their own start.

## Trademarks

This feature is not affiliated with or endorsed by OpenBao a Series of LF Projects, LLC. OpenBao and its logo are trademarks of OpenBao a Series of LF Projects, LLC. All trademarks and copyrights belong to their holders. The logo is used only to identify the software that this feature installs.

The OpenBao logo is from the [OpenBao artwork](https://github.com/openbao/artwork) and is licensed under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Logo: the OpenBao icon from [favicon.svg](https://github.com/openbao/openbao/blob/1d58653b0c00e53484de5af18f20679d78b9fb28/website/public/img/favicon.svg) (MPL-2.0 repository).
