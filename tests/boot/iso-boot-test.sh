#!/bin/bash
# tests/boot/iso-boot-test.sh <iso> <out-dir> [ssh-port] [http-port]
#
# Boots a Kura ISO headless in QEMU with NO internet (user networking with
# restrict=on) and checks, from the host:
#   1. first boot finished            ("First boot complete." on the serial console)
#   2. the Tomo desktop is served      (http://localhost:<http-port>/ → <title>Tomo</title>)
#   3. core services are active        (docker, tomod, first boot, SSH key units; tomo_main on tomo0)
#   4. device identity is recorded     (SSH host key, machine-id, JWT secret hash)
#
# Writes serial.log, report.txt and identity.txt to <out-dir>; exits non-zero
# if any check fails. Compare identity.txt from two boots to prove each boot
# generates its own identity. Needs qemu-system-x86_64, sshpass, curl,
# ssh-keyscan. Uses KVM when /dev/kvm is writable.

set -euo pipefail

ISO="${1:?Usage: $0 <iso> <out-dir> [ssh-port] [http-port]}"
OUT="${2:?Usage: $0 <iso> <out-dir> [ssh-port] [http-port]}"
SSH_PORT="${3:-2222}"
HTTP_PORT="${4:-8080}"
BRAND="${KURA_TEST_BRAND:-kura}"
LOGIN_USER="${KURA_TEST_USER:-admin}"
LOGIN_PASS="${KURA_TEST_PASS:-admin}"

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

desktop_served() {
    curl -fsS --max-time 10 "http://localhost:${HTTP_PORT}/" 2>/dev/null \
        | grep -qF '<title>Tomo</title>'
}

ssh_run() {
    sshpass -p "${LOGIN_PASS}" ssh -p "${SSH_PORT}" \
        -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=10 -o LogLevel=ERROR \
        "${LOGIN_USER}@localhost" "$@"
}

# sudo_run <command>: run one command as root on the guest (password on
# stdin). The command string is passed to the guest shell as-is.
sudo_run() { ssh_run "echo '${LOGIN_PASS}' | sudo -S -p '' $1"; }

ssh_ready() { ssh_run true 2>/dev/null; }

services_active() {
    ssh_run systemctl is-active docker tomod "${BRAND}-firstboot" "${BRAND}-ssh-keygen" \
        >> "${REPORT}"
}

tomo_network_on_tomo0() {
    local bridge
    bridge=$(sudo_run "docker network inspect tomo_main --format '{{index .Options \"com.docker.network.bridge.name\"}}'")
    [ "${bridge}" = "tomo0" ]
}

record_identity() {
    local host_key machine_id jwt
    host_key=$(ssh-keyscan -p "${SSH_PORT}" -t ed25519 localhost 2>/dev/null \
        | ssh-keygen -lf - | awk '{print $2}')
    machine_id=$(ssh_run cat /etc/machine-id)
    jwt=$(sudo_run "sha256sum /opt/tomo/data/secrets/jwt" | awk '{print $1}')
    printf 'ssh_host_key %s\nmachine_id %s\njwt_secret %s\n' \
        "${host_key}" "${machine_id}" "${jwt}" > "${IDENTITY}"
    [ -n "${host_key}" ] && [ -n "${machine_id}" ] && [ -n "${jwt}" ]
}

collect_diagnostics() {
    sudo_run "journalctl -b --no-pager -u docker -u tomod -u ${BRAND}-firstboot -u ${BRAND}-supervisor" \
        > "${OUT}/journal.txt" 2>&1 || true
    { sudo_run "docker ps -a"; sudo_run "docker images"; } > "${OUT}/docker.txt" 2>&1 || true
}

# ---- boot ----

report "Booting ${ISO} (${ACCEL[*]}, wait ${WAIT_SECS}s, no internet)"
qemu-system-x86_64 -m 4096 -smp 2 "${ACCEL[@]}" \
    -cdrom "${ISO}" -boot d \
    -display none -monitor none -serial "file:${SERIAL}" \
    -nic "user,restrict=on,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${HTTP_PORT}-:80" \
    -pidfile "${PIDFILE}" -daemonize

# ---- checks ----

check "first boot finished" wait_for "First boot complete." serial_has "First boot complete."
check "Tomo desktop served offline" wait_for "Tomo desktop on :80" desktop_served
check "SSH login" wait_for "SSH" ssh_ready
check "core services active" services_active
check "tomo_main on bridge tomo0" tomo_network_on_tomo0
check "device identity recorded" record_identity

if [ "${FAILED}" -ne 0 ]; then
    collect_diagnostics
    report "RESULT: FAILED"
    exit 1
fi
report "RESULT: PASSED"
