#!/bin/bash
# tests/boot/boot-test.sh <pc-image(.img|.img.zst)> <out-dir> [ssh-port] [--setup]
#
# Boots a copy of Kura's PC disk image headless in QEMU under UEFI firmware
# (OVMF), with NO internet (user networking with restrict=on). The disk is
# grown by 2 GiB first, as a bigger USB drive would be.
#
# Default: the image as shipped. The default password only reaches a forced
# change (first-login.exp).
# --setup: a kura-setup.json is put on the EFI partition first, as Etchwise
# writes it (new user with a password hash and an SSH key, password logins
# off, hostname, Wi-Fi, time zone); the checks prove it was applied and deleted.
#
# Both modes check first boot, the root partition grown and writable, core
# services, Docker and the device identity, and report (without failing)
# whether less still needs the LESS=-d workaround (issue #6). Writes
# serial.log, report.txt and identity.txt to <out-dir>; exits non-zero if a
# check fails. Needs qemu-system-x86_64, ovmf, mtools, zstd, sshpass, expect,
# openssl, jq. Uses KVM when /dev/kvm is writable.

set -euo pipefail

IMAGE="${1:?Usage: $0 <pc-image> <out-dir> [ssh-port] [--setup]}"
OUT="${2:?Usage: $0 <pc-image> <out-dir> [ssh-port] [--setup]}"
SSH_PORT="${3:-2222}"
SETUP="${4:-}"
BRAND="${KURA_TEST_BRAND:-kura}"
LOGIN_USER="${KURA_TEST_USER:-admin}"
DEFAULT_PASS="${KURA_TEST_PASS:-admin}"
# Set at first login (default mode) or by the setup file (--setup)
LOGIN_PASS="Kura-$(openssl rand -hex 8)"
EFI_OFFSET=$((2048 * 512))   # partition 1 (scripts/x86_64/pc-image.sh)

mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"
SERIAL="${OUT}/serial.log" REPORT="${OUT}/report.txt" IDENTITY="${OUT}/identity.txt"
PIDFILE="${OUT}/qemu.pid" DISK="${OUT}/disk.img" KEY="${OUT}/id_ed25519"
: > "${REPORT}"

if [ -w /dev/kvm ]; then ACCEL=(-accel kvm -cpu host); WAIT_SECS=600
else ACCEL=(-accel tcg); WAIT_SECS=1500; fi

OVMF=""
for f in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF.fd /usr/share/qemu/OVMF.fd; do
    [ -f "${f}" ] && { OVMF="${f}"; break; }
done
[ -n "${OVMF}" ] || { echo "ERROR: no OVMF firmware (install ovmf)" >&2; exit 2; }

stop_vm() { [ -f "${PIDFILE}" ] && kill "$(cat "${PIDFILE}")" 2>/dev/null; rm -f "${PIDFILE}"; }
trap stop_vm EXIT

# shellcheck source=tests/boot/boot-checks.sh
source "$(dirname "$0")/boot-checks.sh"

# ---- disk ----

case "${IMAGE}" in
    *.zst) zstd -q -d -f -o "${DISK}" "${IMAGE}" ;;
    *) cp "${IMAGE}" "${DISK}" ;;
esac
IMAGE_BYTES=$(stat -c %s "${DISK}")
truncate -s +2G "${DISK}"

if [ "${SETUP}" = "--setup" ]; then
    LOGIN_USER="tester"
    ssh-keygen -q -t ed25519 -N "" -C "kura-boot-test" -f "${KEY}"
    jq -n --arg user "${LOGIN_USER}" --arg hash "$(openssl passwd -6 "${LOGIN_PASS}")" \
          --arg key "$(cat "${KEY}.pub")" '{
        version: 1, hostname: "kura-ci",
        user: {name: $user, passwordHash: $hash},
        ssh: {enabled: true, passwordAuth: false, authorizedKeys: [$key]},
        wifi: {ssid: "CIWifi", psk: "password-ci", hidden: false, country: "FR"},
        timezone: "Europe/Paris", keyboard: "fr"}' > "${OUT}/kura-setup.json"
    mcopy -o -i "${DISK}@@${EFI_OFFSET}" "${OUT}/kura-setup.json" ::/kura-setup.json
fi

# ---- boot ----

report "Booting ${IMAGE} ${SETUP} (UEFI, ${ACCEL[*]}, wait ${WAIT_SECS}s, no internet)"
qemu-system-x86_64 -machine q35 -m 4096 -smp 2 "${ACCEL[@]}" -bios "${OVMF}" \
    -drive "file=${DISK},format=raw,if=virtio" \
    -display none -monitor none -serial "file:${SERIAL}" \
    -nic "user,restrict=on,hostfwd=tcp::${SSH_PORT}-:22" \
    -pidfile "${PIDFILE}" -daemonize

# ---- checks ----

check "first boot finished" wait_for "First boot complete." serial_has "First boot complete."
check "SSH reachable" wait_for "SSH" ssh_listening
if [ "${SETUP}" = "--setup" ]; then
    check "setup: SSH key login as the new user" wait_for "key login" ssh_run true
    check "setup: password logins refused" password_login_refused
    check "setup: hostname, Wi-Fi, time zone applied" setup_applied
    check "setup: file deleted from the EFI partition" setup_file_gone
else
    check "first login replaces the default password" first_login_changes_password
fi
check "root partition grown and writable" root_grown "${IMAGE_BYTES}"
check "core services active" services_active
check "Docker answers" docker_answers
check "device identity recorded" record_identity
less_report

if [ "${FAILED}" -ne 0 ]; then
    collect_diagnostics
    report "RESULT: FAILED"
    exit 1
fi
report "RESULT: PASSED"
