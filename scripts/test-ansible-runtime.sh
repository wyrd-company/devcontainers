#!/usr/bin/env bash
#
# Runtime acceptance for the Ansible Feature under s6-overlay.
#
# A throwaway SSH server holds the sample playbook repository. A helper container plays the
# Wyrwood agent: its socket volume holds an SSH agent with the only key the server accepts,
# and a Vault socket that answers a health request. Test containers mount that volume and get
# SSH_AUTH_SOCK and VAULT_ADDR the way a Wyrwood-bound container does. No OpenBao Agent is
# installed. The test uses only Docker volumes and `docker cp`, so it works against a remote
# Docker daemon.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
fixtures="${repo_root}/test/features/ansible"
base_image="${BASE_IMAGE:-$("${repo_root}/scripts/build-base-image.sh" noble)}"
suffix="${RANDOM}-$$"
network="ansible-runtime-${suffix}"
socket_volume="ansible-runtime-sockets-${suffix}"
local_volume="ansible-runtime-local-${suffix}"
git_server="ansible-runtime-git-${suffix}"
helper="ansible-runtime-helper-${suffix}"
git_url=ssh://git@sample-git/srv/git/sample-playbooks.git
state_dir=/var/tmp/ansible-runtime
containers=("${git_server}" "${helper}")

cleanup() {
    docker rm --force "${containers[@]}" >/dev/null 2>&1 || true
    docker network rm "${network}" >/dev/null 2>&1 || true
    docker volume rm "${socket_volume}" "${local_volume}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    for name in "${containers[@]}"; do
        echo "--- logs: ${name}" >&2
        docker logs --tail 60 "${name}" >&2 2>&1 || true
    done
    exit 1
}

assert_eq() {
    [ "$2" = "$3" ] || fail "$1: expected '$2', got '$3'"
}

wait_for() {
    local description="$1"
    shift
    for _ in $(seq 1 240); do
        if "$@" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.5
    done
    fail "Timed out waiting for ${description}."
}

# --- Images -----------------------------------------------------------------------------

build_image() {
    local tag="$1"
    shift
    docker build \
        --quiet \
        --file "${fixtures}/runtime.Dockerfile" \
        --build-arg "BASE_IMAGE=${base_image}" \
        --build-arg REQUIREMENTS=requirements.yml \
        --build-arg "ARGS=-e sample_extra=on" \
        "$@" \
        --tag "${tag}" \
        "${repo_root}" >/dev/null
}

root_image="ansible-runtime:root-${suffix}"
user_image="ansible-runtime:user-${suffix}"
local_image="ansible-runtime:local-${suffix}"
build_image "${root_image}" --build-arg "SOURCE=${git_url}"
# The user image remaps the vscode user ID the way the Dev Containers CLI does on a host whose
# user ID is not 1000.
build_image "${user_image}" --build-arg "SOURCE=${git_url}" --build-arg SERVICEUSER=vscode --build-arg REMAP_UID=1234
build_image "${local_image}" --build-arg SOURCE=/srv/sample-playbooks
docker build --quiet --file "${fixtures}/git-server.Dockerfile" --tag "ansible-runtime-git:${suffix}" "${fixtures}" >/dev/null

"${repo_root}/scripts/check-sudo-no-all.sh" "${root_image}"

# --- Services around the Feature ---------------------------------------------------------

docker network create "${network}" >/dev/null
docker volume create "${socket_volume}" >/dev/null

docker run --detach --name "${git_server}" --network "${network}" --network-alias sample-git \
    "ansible-runtime-git:${suffix}" >/dev/null
docker cp "${fixtures}/playbooks" "${git_server}:/fixtures"
docker cp "${fixtures}/role-fixture" "${git_server}:/role-fixture"
docker cp "${fixtures}/dep-fixture" "${git_server}:/dep-fixture"

# OpenSSH's own agent serves only its owner and root, so the simulated agent runs as the
# vscode user. The real Wyrwood agent grants access through a group instead.
docker create --name "${helper}" --entrypoint /bin/bash \
    --mount "type=volume,src=${socket_volume},dst=/run/wyrwood" \
    "${user_image}" -c '
        set -e
        chmod 0777 /run/wyrwood
        setpriv --reuid=vscode --regid=vscode --init-groups bash -c "
            set -e
            ssh-keygen -q -t ed25519 -N \"\" -f /tmp/sample-key
            eval \"\$(ssh-agent -a /run/wyrwood/ssh-agent.sock)\" >/dev/null
            ssh-add /tmp/sample-key 2>/dev/null
            chmod 0666 /run/wyrwood/ssh-agent.sock
        "
        exec python3 -I /opt/fake-vault.py /run/wyrwood/vault.sock
    ' >/dev/null
docker cp "${fixtures}/fake-vault.py" "${helper}:/opt/fake-vault.py"
docker start "${helper}" >/dev/null
wait_for "the Wyrwood socket simulation" docker exec "${helper}" test -S /run/wyrwood/vault.sock -a -S /run/wyrwood/ssh-agent.sock

public_key="$(docker exec "${helper}" cat /tmp/sample-key.pub)"
wait_for "the Git server" docker exec "${git_server}" nc -z 127.0.0.1 22
docker exec "${git_server}" sh -c \
    "printf '%s\n' '${public_key}' >/home/git/.ssh/authorized_keys && chown git:git /home/git/.ssh/authorized_keys && chmod 0600 /home/git/.ssh/authorized_keys"

git_as_git() {
    docker exec --user git \
        --env GIT_AUTHOR_NAME=sample-author --env GIT_AUTHOR_EMAIL=sample-author@example.test \
        --env GIT_COMMITTER_NAME=sample-author --env GIT_COMMITTER_EMAIL=sample-author@example.test \
        "${git_server}" sh -c "$1"
}

git_as_git '
    set -e
    git init -q --bare -b main /srv/git/sample-playbooks.git
    git init -q --bare -b main /srv/git/sample-role.git
    git init -q --bare -b main /srv/git/sample-dep.git
    git clone -q /srv/git/sample-dep.git /tmp/dep 2>/dev/null
    cd /tmp/dep
    git checkout -q -B main
    cp -r /dep-fixture/. .
    git add -A
    git commit -qm "Add the sample dependency"
    git tag dep-v1
    git push -q origin main dep-v1
    git clone -q /srv/git/sample-role.git /tmp/role 2>/dev/null
    cd /tmp/role
    git checkout -q -B main
    cp -r /role-fixture/. .
    git add -A
    git commit -qm "Add the sample role"
    git tag role-v1
    git push -q origin main role-v1
    git clone -q /srv/git/sample-playbooks.git /tmp/work 2>/dev/null
    cd /tmp/work
    git checkout -q -B main
    cp -r /fixtures/good/. .
    echo marker-1 >marker.txt
    git add -A
    git commit -qm "Add the sample playbook"
    git push -q origin main
'

# commit_playbook <marker> <fixture>: publish a new playbook commit.
commit_playbook() {
    git_as_git "
        set -e
        cd /tmp/work
        cp /fixtures/$2/site.yml site.yml
        echo $1 >marker.txt
        git add -A
        git commit -qm 'Change to $1'
        git push -q origin main
    "
}

# commit_requirements <role tag>: publish a requirements file that selects another role version.
commit_requirements() {
    git_as_git "
        set -e
        cd /tmp/work
        sed -i 's/^    version: .*/    version: $1/' requirements.yml
        git add -A
        git commit -qm 'Require $1'
        git push -q origin main
    "
}

# publish_role <role tag> <dependency tag>: publish new versions of the sample role and of the
# dependency that the role requires.
publish_role() {
    git_as_git "
        set -e
        cd /tmp/dep
        sed -i 's/dep-v[0-9]*/$2/' tasks/main.yml
        git add -A
        git commit -qm 'Release $2'
        git tag $2
        git push -q origin main $2
        cd /tmp/role
        sed -i 's/role-v[0-9]*/$1/' tasks/main.yml
        sed -i 's/dep-v[0-9]*/$2/' meta/main.yml
        git add -A
        git commit -qm 'Release $1'
        git tag $1
        git push -q origin main $1
    "
}

# --- Containers --------------------------------------------------------------------------

start_container() {
    local name="$1"
    local image="$2"
    shift 2
    containers+=("${name}")
    docker run --detach \
        --name "${name}" \
        --network "${network}" \
        --mount "type=volume,src=${socket_volume},dst=/run/wyrwood" \
        --env SSH_AUTH_SOCK=/run/wyrwood/ssh-agent.sock \
        --env VAULT_ADDR=unix:///run/wyrwood/vault.sock \
        --env SAMPLE_RUNTIME_VALUE=sample-runtime-value \
        --env ANSIBLE_INVENTORY=/nonexistent/inventory \
        "$@" \
        "${image}" >/dev/null
}

# --no-lock keeps this poll from taking the s6-rc lock that a starting container needs.
setup_done() {
    docker exec --user root "$1" /command/s6-rc --no-lock -a list | grep -qx ansible-setup
}

state_value() {
    docker exec "$1" sed -n "s/^$2=//p" "${state_dir}/state"
}

run_count() {
    docker exec "$1" grep -c '^start$' "${state_dir}/timeline"
}

root_name="ansible-runtime-root-${suffix}"
start_container "${root_name}" "${root_image}"
wait_for "ansible-setup to finish" setup_done "${root_name}"

echo "== First clone and apply"
assert_eq "service user" root "$(state_value "${root_name}" user)"
assert_eq "playbook ran against the container" localhost "$(state_value "${root_name}" host)"
assert_eq "playbook source" marker-1 "$(state_value "${root_name}" marker)"
assert_eq "extra arguments" on "$(state_value "${root_name}" extra)"
role_version() {
    docker exec "$1" sh -c "tr -d '\n' <${state_dir}/role-ran"
}
dep_version() {
    docker exec "$1" sh -c "tr -d '\n' <${state_dir}/dep-ran"
}
assert_eq "the role from the requirements file ran" role-v1 "$(role_version "${root_name}")"
assert_eq "the role's dependency ran" dep-v1 "$(dep_version "${root_name}")"
assert_eq "HOME of the service user" /root "$(state_value "${root_name}" home)"
assert_eq "USER of the service user" root "$(state_value "${root_name}" login_user)"
assert_eq "LOGNAME of the service user" root "$(state_value "${root_name}" logname)"
assert_eq "startup runs once" 1 "$(run_count "${root_name}")"
server_head="$(git_as_git 'git -C /srv/git/sample-playbooks.git rev-parse --short HEAD')"
assert_eq "checkout commit" "${server_head}" "$(docker exec "${root_name}" git -C /var/lib/ansible-setup/checkout rev-parse --short HEAD)"
docker exec "${root_name}" sh -c 'test "$(stat -c %U /var/lib/ansible-setup/checkout)" = root' \
    || fail "The checkout is not owned by the service user."

echo "== The environment reaches the playbook unchanged"
assert_eq "SSH_AUTH_SOCK" /run/wyrwood/ssh-agent.sock "$(state_value "${root_name}" ssh_auth_sock)"
assert_eq "VAULT_ADDR" unix:///run/wyrwood/vault.sock "$(state_value "${root_name}" vault_addr)"
assert_eq "no SSH_AGENT_SOCK is invented" unset "$(state_value "${root_name}" ssh_agent_sock)"
assert_eq "no BAO_ADDR is invented" unset "$(state_value "${root_name}" bao_addr)"
assert_eq "other container variables" sample-runtime-value "$(state_value "${root_name}" sample)"
assert_eq "the Vault socket answered" True "$(state_value "${root_name}" vault_health)"
assert_eq "the container environment" /nonexistent/inventory "$(state_value "${root_name}" inventory_env)"
assert_eq "the inventory flag beats ANSIBLE_INVENTORY" localhost "$(state_value "${root_name}" host)"

echo "== No OpenBao Agent dependency"
docker exec "${root_name}" test ! -e /etc/s6-overlay/s6-rc.d/openbao-secrets || fail "openbao-secrets exists."
docker exec "${root_name}" test ! -e /etc/s6-overlay/s6-rc.d/openbao-agent || fail "openbao-agent exists."
docker exec "${root_name}" sh -c 'test ! -e /usr/local/bin/bao'
docker exec "${root_name}" sh -c "grep -rEq 'openbao|secrets' /etc/ansible-setup /etc/s6-overlay/s6-rc.d/ansible-setup" \
    && fail "The Feature refers to OpenBao Agent or a secret file."

echo "== A service that depends on ansible-setup starts after it"
wait_for "the dependent service" docker exec "${root_name}" test -e /var/tmp/sample-dependent-started

echo "== Update and apply"
commit_playbook marker-2 good
docker exec --user root "${root_name}" ansible-sync >/dev/null
assert_eq "updated source" marker-2 "$(state_value "${root_name}" marker)"
assert_eq "second run" 2 "$(run_count "${root_name}")"

echo "== A changed requirements version replaces the installed role"
publish_role role-v2 dep-v2
commit_requirements role-v2
docker exec --user root "${root_name}" ansible-sync >/dev/null
assert_eq "role after the requirements change" role-v2 "$(role_version "${root_name}")"
assert_eq "dependency after the requirements change" dep-v2 "$(dep_version "${root_name}")"

echo "== ansible-sync is limited to the service user"
if docker exec --user vscode "${root_name}" ansible-sync >/dev/null 2>&1; then
    fail "ansible-sync ran for a user other than the service user."
fi

echo "== ansible-sync serializes with startup and with itself"
docker exec "${root_name}" sh -c "rm -f ${state_dir}/timeline && touch ${state_dir}/slow"
docker exec --user root "${root_name}" ansible-sync >/dev/null &
first_sync=$!
sleep 1.5
docker exec --user root "${root_name}" sh -c '/command/s6-rc -d change ansible-setup && /command/s6-rc -u change ansible-setup' >/dev/null &
startup_run=$!
sleep 0.5
docker exec --user root "${root_name}" ansible-sync >/dev/null &
second_sync=$!
wait "${first_sync}" "${startup_run}" "${second_sync}" || fail "A serialized run failed."
docker exec "${root_name}" rm -f "${state_dir}/slow"
assert_eq "runs do not overlap" "start end start end start end" \
    "$(docker exec "${root_name}" sh -c "tr '\n' ' ' <${state_dir}/timeline" | sed 's/ $//')"

echo "== A failing playbook fails ansible-sync and blocks dependents on the next start"
commit_playbook marker-3 failing
if docker exec --user root "${root_name}" ansible-sync >/dev/null 2>&1; then
    fail "ansible-sync succeeded with a failing playbook."
fi
docker exec --user root "${root_name}" rm -f /var/tmp/sample-dependent-started
docker restart "${root_name}" >/dev/null
wait_for "the failed startup run" sh -c "docker logs '${root_name}' 2>&1 | grep -q 'ansible-playbook failed'"
sleep 3
assert_eq "container state" true "$(docker inspect --format '{{.State.Running}}' "${root_name}")"
if setup_done "${root_name}"; then
    fail "ansible-setup reported success after a failing playbook."
fi
docker exec "${root_name}" test ! -e /var/tmp/sample-dependent-started \
    || fail "A dependent service started although ansible-setup failed."

echo "== A fixed playbook recovers"
commit_playbook marker-4 good
docker exec --user root "${root_name}" ansible-sync >/dev/null
assert_eq "recovered source" marker-4 "$(state_value "${root_name}" marker)"
if setup_done "${root_name}"; then
    fail "ansible-sync alone marked ansible-setup up."
fi
echo "== The documented recovery starts ansible-setup and its dependents"
docker exec --user root "${root_name}" /command/s6-rc -u change user >/dev/null
wait_for "ansible-setup after s6-rc recovery" setup_done "${root_name}"
wait_for "the dependent service after s6-rc recovery" docker exec "${root_name}" test -e /var/tmp/sample-dependent-started
echo "== A restart applies the playbook again"
docker restart "${root_name}" >/dev/null
wait_for "ansible-setup after the restart" setup_done "${root_name}"
wait_for "the dependent service after the restart" docker exec "${root_name}" test -e /var/tmp/sample-dependent-started

echo "== An unavailable repository fails and leaves the checkout alone"
before_runs="$(run_count "${root_name}")"
before_head="$(docker exec "${root_name}" git -C /var/lib/ansible-setup/checkout rev-parse HEAD)"
docker stop "${git_server}" >/dev/null
if output="$(docker exec --user root "${root_name}" ansible-sync 2>&1)"; then
    fail "ansible-sync succeeded without a repository."
fi
printf '%s\n' "${output}" | grep -Fq "Unable to fetch" || fail "The failure did not name the fetch: ${output}"
assert_eq "no playbook ran" "${before_runs}" "$(run_count "${root_name}")"
assert_eq "checkout commit" "${before_head}" "$(docker exec "${root_name}" git -C /var/lib/ansible-setup/checkout rev-parse HEAD)"
docker start "${git_server}" >/dev/null
wait_for "the Git server to return" docker exec --user root "${root_name}" ansible-sync

echo "== A non-root service user"
user_name="ansible-runtime-user-${suffix}"
start_container "${user_name}" "${user_image}"
wait_for "ansible-setup for the non-root user" setup_done "${user_name}"
assert_eq "service user" vscode "$(state_value "${user_name}" user)"
assert_eq "Git reached the repository through the agent socket" marker-4 "$(state_value "${user_name}" marker)"
docker exec "${user_name}" sh -c 'test "$(stat -c %u /var/lib/ansible-setup/checkout)" = 1234 && test "$(stat -c %u /var/lib/ansible-setup)" = 1234' \
    || fail "The checkout or state directory is not owned by the remapped service user."
docker exec --user vscode --env HOME=/tmp/sample-wrong-home --env USER=sample-wrong --env LOGNAME=sample-wrong \
    "${user_name}" ansible-sync >/dev/null
assert_eq "HOME of a direct call" /home/vscode "$(state_value "${user_name}" home)"
assert_eq "USER of a direct call" vscode "$(state_value "${user_name}" login_user)"
assert_eq "LOGNAME of a direct call" vscode "$(state_value "${user_name}" logname)"
docker exec --user root "${user_name}" ansible-sync >/dev/null
assert_eq "service user after root called ansible-sync" vscode "$(state_value "${user_name}" user)"
if docker exec --user nobody "${user_name}" ansible-sync >/dev/null 2>&1; then
    fail "ansible-sync ran for a user other than the service user."
fi

echo "== A local directory source"
local_helper="ansible-runtime-local-helper-${suffix}"
containers+=("${local_helper}")
docker create --name "${local_helper}" --mount "type=volume,src=${local_volume},dst=/srv/sample-playbooks" "${local_image}" >/dev/null
docker cp "${fixtures}/playbooks/good/." "${local_helper}:/srv/sample-playbooks"
docker rm "${local_helper}" >/dev/null
local_name="ansible-runtime-local-${suffix}"
start_container "${local_name}" "${local_image}" --mount "type=volume,src=${local_volume},dst=/srv/sample-playbooks"
docker exec "${local_name}" true
docker exec --user root "${local_name}" sh -c 'echo marker-local-1 >/srv/sample-playbooks/marker.txt'
docker exec --user root "${local_name}" ansible-sync >/dev/null
assert_eq "local source" marker-local-1 "$(state_value "${local_name}" marker)"
docker exec --user root "${local_name}" sh -c 'echo marker-local-2 >/srv/sample-playbooks/marker.txt'
docker exec --user root "${local_name}" ansible-sync >/dev/null
assert_eq "edited local source" marker-local-2 "$(state_value "${local_name}" marker)"
docker exec "${local_name}" sh -c 'test ! -e /srv/sample-playbooks/.git && test ! -e /var/lib/ansible-setup/checkout' \
    || fail "A local source was cloned or copied."

# --- Installer validation ----------------------------------------------------------------

assert_install_rejected() {
    local description="$1"
    local expected="$2"
    shift 2
    local rejecter="ansible-runtime-reject-${suffix}"
    local output

    containers+=("${rejecter}")
    docker create --name "${rejecter}" --entrypoint /bin/bash "${base_image}" \
        -c 'env "$@" /feature/install.sh' bash \
        SOURCE= PLAYBOOK=site.yml REF= INVENTORY= REQUIREMENTS= ARGS= \
        CHECKOUTDIR=/var/lib/ansible-setup/checkout SERVICEUSER=root _REMOTE_USER=vscode \
        "$@" >/dev/null
    docker cp "${repo_root}/src/features/ansible" "${rejecter}:/feature"
    if output="$(docker start --attach "${rejecter}" 2>&1)"; then
        docker rm "${rejecter}" >/dev/null
        fail "Invalid configuration was accepted: ${description}."
    fi
    docker rm "${rejecter}" >/dev/null
    printf '%s\n' "${output}" | grep -Fq "${expected}" \
        || fail "Configuration was rejected for the wrong reason: ${description}. ${output}"
}

echo "== Installer validation"
assert_install_rejected "a token in the URL" "must not embed credentials" \
    SOURCE=https://sample-user:sample-token@example.test/sample/repo.git
assert_install_rejected "a password in an ssh URL" "must not embed a password" \
    SOURCE=ssh://git:sample-token@example.test/sample/repo.git
assert_install_rejected "an unsupported transport" "source must be" SOURCE=ext::sample-command
assert_install_rejected "a relative local path" "source must be" SOURCE=sample-dir
assert_install_rejected "a ref with a local directory" "ref is not valid with a local directory" \
    SOURCE=/srv/sample-playbooks REF=main
assert_install_rejected "a playbook that leaves the source" "must be a relative path" PLAYBOOK=../sample.yml
assert_install_rejected "a playbook with a parent component" "must not contain" PLAYBOOK=a/../sample.yml
assert_install_rejected "an absolute playbook" "must be a relative path" PLAYBOOK=/etc/sample.yml
assert_install_rejected "an inventory that leaves the source" "must not contain" INVENTORY=a/../../b
assert_install_rejected "quotes in args" "args contains characters" "ARGS=-e 'sample=1'"
assert_install_rejected "braces in args" "args contains characters" 'ARGS=-e {sample:1}'
assert_install_rejected "a ref with a space" "ref must be" "REF=main branch"
assert_install_rejected "a relative checkout directory" "checkoutDir must be an absolute path" CHECKOUTDIR=sample
assert_install_rejected "a checkout directory that holds the lock" "must not contain /var/lib/ansible-setup/lock" \
    CHECKOUTDIR=/var/lib/ansible-setup
assert_install_rejected "a checkout directory inside the lock path" "must not be /var/lib/ansible-setup/lock or inside it" \
    CHECKOUTDIR=/var/lib/ansible-setup/lock/checkout
assert_install_rejected "an unknown service user" "does not exist" SERVICEUSER=sample-missing-user

printf 'Ansible s6 runtime checks passed.\n'
