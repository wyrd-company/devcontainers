---
ansible: major
---

Adds the Ansible Feature. It installs Ansible, applies a playbook at container startup through the ansible-setup s6 oneshot, and provides the ansible-sync command to update the playbook source and apply the playbook again.
