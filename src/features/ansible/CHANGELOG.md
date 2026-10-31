# Changelog

## 1.0.0

Graduates from `0.x` to `1.0.0`.

### Breaking

- Adds the Ansible Feature. It installs Ansible, applies a playbook at container startup through the ansible-setup s6 oneshot, and provides the ansible-sync command to update the playbook source and apply the playbook again. The optional `sudoUser` option lets one user run `sudo ansible-sync` and nothing else.
