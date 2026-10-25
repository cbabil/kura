#!/bin/bash
# tests/boot/iso-boot-test.sh <iso> <out-dir> [ssh-port]
#
# Boots a Kura ISO headless in QEMU with NO internet (user networking with
# restrict=on) and checks, from the host:
#   1. first boot finished            ("First boot complete." on the serial console)
#   2. the default password is expired  (the first login gets no shell and must set a new one)
#   3. core services are active        (docker, first boot, SSH key units)
#   4. Docker answers                  (docker info as root)
#   5. device identity is recorded     (SSH host key, machine-id)
#
# Writes serial.log, report.txt and identity.txt to <out-dir>; exits non-zero
# if any check fails. Compare identity.txt from two boots to prove each boot
# generates its own identity. Needs qemu-system-x86_64, sshpass, expect,
# ssh-keyscan. Uses KVM when /dev/kvm is writable.

set -euo pipefail

ISO="${1:?Usage: $0 <iso> <out-dir> [ssh-port]}"
OUT="${2:?Usage: $0 <iso> <out-dir> [ssh-port]}"
SSH_PORT="${3:-2222}"
BRAND="${KURA_TEST_BRAND:-kura}"
LOGIN_USER="${KURA_TEST_USER:-admin}"
DEFAULT_PASS="${KURA_TEST_PASS:-admin}"
# Set at first login, which must replace the image's default password
LOGIN_PASS="Kura-$(openssl rand -hex 8)"

mkdir -p "${OUT}"
SERIAL="${OUT}/serial.log"
REPORT="${OUT}/report.txt"
IDENTITY="${OUT}/identity.txt"
PIDFILE="${OUT}/qemu.pid"
: > "${REPORT}"

if [ -w /dev/kvm ]; then
    ACCEL=(-accel kvm -cpu host)
    WAIT_SECS=600
else
    ACCEL=(-accel tcg)
    WAIT_SECS=1500
fi

stop_vm() {
    if [ -f "${PIDFILE}" ]; then
        kill "$(cat "${PIDFILE}")" 2>/dev/null || true
        rm -f "${PIDFILE}"
    fi
}
trap stop_vm EXIT

# ---- helpers ----
# QEMU's user networking forwards IPv4 only: use 127.0.0.1, never localhost
# (ssh-keyscan stops at localhost's IPv6 address).

report() { echo "$*" | tee -a "${REPORT}"; }

# wait_for <description> <command...>: poll every 10 s until the command
# succeeds or WAIT_SECS pass.
wait_for() {
    local what="$1" deadline=$(( SECONDS + WAIT_SECS ))
    shift
    until "$@"; do
        if [ "${SECONDS}" -ge "${deadline}" ]; then
            report "  timed out after ${WAIT_SECS}s waiting for: ${what}"
            return 1
        fi
        sleep 10
    done
}

# check <name> <command...>: record PASS/FAIL without stopping the run.
FAILED=0
check() {
    local name="$1"
    shift
    if "$@"; then
        report "PASS ${name}"
    else
        report "FAIL ${name}"
        FAILED=1
    fi
}

serial_has() { grep -qF "$1" "${SERIAL}" 2>/dev/null; }

ssh_run() {
    sshpass -p "${LOGIN_PASS}" ssh -p "${SSH_PORT}" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 -o LogLevel=ERROR \
        "${LOGIN_USER}@127.0.0.1" "$@"
}

# sudo_run <command>: run one command as root on the guest (password on
# stdin). The command string is passed to the guest shell as-is.
sudo_run() { ssh_run "echo '${LOGIN_PASS}' | sudo -S -p '' $1"; }

ssh_listening() { ssh-keyscan -p "${SSH_PORT}" -T 5 127.0.0.1 2>/dev/null | grep -q .; }

# The default password must only reach a forced password change (first-login.exp
# fails if it gets a shell); from then on LOGIN_PASS is the password.
first_login_changes_password() {
    "$(dirname "$0")/first-login.exp" "${SSH_PORT}" "${LOGIN_USER}" "${DEFAULT_PASS}" "${LOGIN_PASS}" \
        > "${OUT}/first-login.log" 2>&1 || return 1
    ssh_run true
}

# systemctl is-active exits 0 if ANY listed unit is active, so check each
# unit's own state line.
services_active() {
    local states
    states=$(ssh_run systemctl is-active docker "${BRAND}-firstboot" "${BRAND}-ssh-keygen" \
        || true)
    # shellcheck disable=SC2001  # indent every line, not one substitution
    sed 's/^/  /' <<< "${states}" >> "${REPORT}"
    [ "$(echo "${states}" | grep -cx active)" -eq 3 ]
}

docker_answers() { sudo_run "docker info --format '{{.ServerVersion}}'" | grep -q .; }

record_identity() {
    local host_key machine_id
    host_key=$(ssh-keyscan -p "${SSH_PORT}" -t ed25519 127.0.0.1 2>/dev/null \
        | ssh-keygen -lf - | awk '{print $2}')
    machine_id=$(ssh_run cat /etc/machine-id)
    printf 'ssh_host_key %s\nmachine_id %s\n' "${host_key}" "${machine_id}" > "${IDENTITY}"
    [ -n "${host_key}" ] && [ -n "${machine_id}" ]
}

collect_diagnostics() {
    sudo_run "journalctl -b --no-pager -u docker -u ${BRAND}-firstboot" \
        > "${OUT}/journal.txt" 2>&1 || true
    { sudo_run "docker ps -a"; sudo_run "docker images"; } > "${OUT}/docker.txt" 2>&1 || true
}

# ---- boot ----

report "Booting ${ISO} (${ACCEL[*]}, wait ${WAIT_SECS}s, no internet)"
qemu-system-x86_64 -m 4096 -smp 2 "${ACCEL[@]}" \
    -cdrom "${ISO}" -boot d \
    -display none -monitor none -serial "file:${SERIAL}" \
    -nic "user,restrict=on,hostfwd=tcp::${SSH_PORT}-:22" \
    -pidfile "${PIDFILE}" -daemonize

# ---- checks ----

check "first boot finished" wait_for "First boot complete." serial_has "First boot complete."
check "SSH reachable" wait_for "SSH" ssh_listening
check "first login replaces the default password" first_login_changes_password
check "core services active" services_active
check "Docker answers" docker_answers
check "device identity recorded" record_identity

if [ "${FAILED}" -ne 0 ]; then
    collect_diagnostics
    report "RESULT: FAILED"
    exit 1
fi
report "RESULT: PASSED"
