# Changelog

## 1.1.0

### Features

- When the Ansible Feature is installed, the services of this Feature start after its `ansible-setup` oneshot succeeds. Without Ansible, startup does not change. The Feature adds the Ansible Feature to `installsAfter`.

## 1.0.0

### Features

- Runs Docker daemons for child containers as native s6-overlay services. The services are `containerd` and `dockerd`.
- Based on the Microsoft Docker-in-Docker feature. This feature uses s6-overlay supervision instead of an entrypoint hook, so an image with s6-overlay as PID 1 works.
- Installs Docker CE by default. Option `moby` selects Microsoft-packaged Moby. The install fails if the Moby packages are not available.
