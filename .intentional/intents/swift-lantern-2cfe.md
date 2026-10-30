---
caddy: minor
codex-cli: minor
dagu: minor
docker-in-docker: minor
docker-outside-of-docker: minor
openbao-agent: minor
opencodex: minor
openobserve: minor
opentelemetry-collector: minor
sshd: minor
t3code-server: minor
---

When the Ansible Feature is installed, the services of this Feature start after its `ansible-setup` oneshot succeeds. Without Ansible, startup does not change. The Feature adds the Ansible Feature to `installsAfter`.
