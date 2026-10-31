# Changelog

## 1.1.0

### Features

- When the Ansible Feature is installed, the services of this Feature start after its `ansible-setup` oneshot succeeds. Without Ansible, startup does not change. The Feature adds the Ansible Feature to `installsAfter`.

## 1.0.1

### Fixes

- Caddy installs from the official release package on GitHub. The old apt repository used an expired signing key, so the install failed.
- The installer checks the package against the release checksums and rejects a version that is not a semantic version.

## 1.0.0

### Features

- Installs Caddy and runs it as an s6-overlay service.
- A second service reloads Caddy when you add, change or remove a `.caddy` file in `/etc/caddy/conf.d`. A reload that fails validation keeps the active configuration.
- Other features can list the DNS names they need in `/etc/caddy/required-hosts.d`. Caddy waits until these names resolve before it starts or reloads.
- Options `acmeCa` and `acmeCaRoot` select an ACME certificate authority. Option `configUser` selects the user who manages the fragments.
