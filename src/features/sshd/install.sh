#!/usr/bin/env bash
#-------------------------------------------------------------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# Licensed under the MIT License. See https://go.microsoft.com/fwlink/?linkid=2090316 for license information.
#-------------------------------------------------------------------------------------------------------------
#
# Docs: https://github.com/microsoft/vscode-dev-containers/blob/main/script-library/docs/sshd.md
# Maintainer: The VS Code and Codespaces Teams
#
SSHD_PORT="${SSHD_PORT:-"2222"}"
USERNAME="${USERNAME:-"${_REMOTE_USER:-"automatic"}"}"
GATEWAY_PORTS="${GATEWAYPORTS:-"no"}"

set -e

# Clean up
rm -rf /var/lib/apt/lists/*

if [ "$(id -u)" -ne 0 ]; then
    echo -e 'Script must be run as root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
    exit 1
fi

# Determine the appropriate non-root user
if [ "${USERNAME}" = "auto" ] || [ "${USERNAME}" = "automatic" ]; then
    USERNAME=""
    POSSIBLE_USERS=("vscode" "node" "codespace" "$(awk -v val=1000 -F ":" '$3==val{print $1}' /etc/passwd)")
    for CURRENT_USER in "${POSSIBLE_USERS[@]}"; do
        if id -u ${CURRENT_USER} > /dev/null 2>&1; then
            USERNAME=${CURRENT_USER}
            break
        fi
    done
    if [ "${USERNAME}" = "" ]; then
        USERNAME=root
    fi
elif [ "${USERNAME}" = "none" ] || ! id -u ${USERNAME} > /dev/null 2>&1; then
    USERNAME=root
fi

apt_get_update()
{
    if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
        echo "Running apt-get update..."
        apt-get update -y
    fi
}

# Checks if packages are installed and installs them if not
check_packages() {
    if ! dpkg -s "$@" > /dev/null 2>&1; then
        apt_get_update
        apt-get -y install --no-install-recommends "$@"
    fi
}

# Ensure apt is in non-interactive to avoid prompts
export DEBIAN_FRONTEND=noninteractive

# Install openssh-server openssh-client
check_packages openssh-server openssh-client lsof

if [ $(getent group ssh) ]; then
  echo "'ssh' group already exists."
else
  echo "adding 'ssh' group, as it does not already exist."
  groupadd ssh
fi

# Add user to ssh group
if [ "${USERNAME}" != "root" ]; then
    usermod -aG ssh ${USERNAME}
fi

# Setup sshd
mkdir -p /var/run/sshd
sed -i 's/session\s*required\s*pam_loginuid\.so/session optional pam_loginuid.so/g' /etc/pam.d/sshd
sed -i -E "s/#*\s*Port\s+.+/Port ${SSHD_PORT}/g" /etc/ssh/sshd_config
sed -i "s/#GatewayPorts no/GatewayPorts ${GATEWAY_PORTS}/g" /etc/ssh/sshd_config
# Need to UsePAM so /etc/environment is processed
sed -i -E "s/#?\s*UsePAM\s+.+/UsePAM yes/g" /etc/ssh/sshd_config

# Included files are processed before the main configuration. OpenSSH uses the
# first value it obtains, so this file sorts first to enforce key-only access.
cat >/etc/ssh/sshd_config.d/00-devcontainer-key-only.conf <<EOF
AuthenticationMethods publickey
KbdInteractiveAuthentication no
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
EOF

# Register sshd as a native s6-rc longrun service.
for required_path in /init /etc/s6-overlay/s6-rc.d /etc/s6-overlay/user-bundles.d/user/contents.d; do
    if [ ! -e "${required_path}" ]; then
        echo "The sshd Feature requires an s6-overlay 3 image with /init as PID 1." >&2
        exit 1
    fi
done

# Host keys are generated into /etc/ssh by `ssh-keygen -A` below. They act as
# a build-time seed: the s6 run script copies them into /etc/ssh/keys (a named
# volume) on first boot, so the server fingerprint survives container rebuilds.
ssh-keygen -A

cat >/etc/ssh/sshd_config.d/10-persistent-host-keys.conf <<EOF
HostKey /etc/ssh/keys/ssh_host_rsa_key
HostKey /etc/ssh/keys/ssh_host_ecdsa_key
HostKey /etc/ssh/keys/ssh_host_ed25519_key
EOF

service_dir="/etc/s6-overlay/s6-rc.d/sshd"
mkdir -p "${service_dir}/dependencies.d"
printf 'longrun\n' > "${service_dir}/type"
touch "${service_dir}/dependencies.d/base"
if [ -d /etc/s6-overlay/s6-rc.d/ansible-setup ]; then
    touch "${service_dir}/dependencies.d/ansible-setup"
fi
touch /etc/s6-overlay/user-bundles.d/user/contents.d/sshd

tee "${service_dir}/run" > /dev/null << 'EOF'
#!/command/with-contenv sh
mkdir -p /run/sshd /etc/ssh/keys
# Seed the persistent host-key volume from the image on first boot; generate
# on the spot if the volume is empty and the image has no seed (e.g. the
# Feature was installed without running ssh-keygen).
for keytype in rsa ecdsa ed25519; do
    key="/etc/ssh/keys/ssh_host_${keytype}_key"
    if [ ! -f "${key}" ]; then
        if [ -f "/etc/ssh/ssh_host_${keytype}_key" ]; then
            cp "/etc/ssh/ssh_host_${keytype}_key" "${key}"
            cp "/etc/ssh/ssh_host_${keytype}_key.pub" "${key}.pub"
        else
            ssh-keygen -t "${keytype}" -N '' -f "${key}"
        fi
        chmod 0600 "${key}"
        chmod 0644 "${key}.pub"
    fi
done
exec /usr/sbin/sshd -D -e
EOF
chmod 0755 "${service_dir}/run"

echo -e "Done!\n\n- Port: ${SSHD_PORT}\n- User: ${USERNAME}"
echo "- Authentication: public key only"

rm -rf /var/lib/apt/lists/*
