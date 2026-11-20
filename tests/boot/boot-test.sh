#!/bin/bash
# tests/boot/boot-test.sh <pc-image(.img|.img.zst)> <out-dir> [ssh-port] [--setup|--installed]
#
# Boots a copy of Kura's PC disk image headless in QEMU under UEFI firmware
# (OVMF) with Secure Boot on and Microsoft's keys enrolled, as on a NUC, with
# NO internet (user networking with restrict=on). The disk is grown by 2 GiB
# first, as a bigger USB drive would be.
#
# Default: the image as shipped. Its public default password is replaced at
# first boot by a one-time password, read from the login screen on the serial
# console, which only reaches a forced change (first-login.exp).
# --setup: a kura-setup.json is put on the EFI partition first, as Etchwise
# writes it (new user with a password hash and an SSH key, password logins
# off, hostname, Wi-Fi, time zone, a disk layout); the checks prove it was
# applied and deleted. KURA_TEST_LAYOUT=full asks for the full custom layout
# (/var, /var/lib, /tmp, a folder of its own and swap as volumes) instead of
# the Server one (boot-checks.sh), and runs only the checks the layout can
# affect, on a smaller VM, since a Server boot covers the rest.
# --installed: the disk is one the PC installer wrote (installer-test.sh),
# which already holds that setup file; the user's password comes from
# KURA_TEST_LOGIN_PASS, the SSH key is <out-dir>/id_ed25519, and the image's
# size from KURA_TEST_IMAGE_BYTES. Checked like --setup.
#
# Every mode checks Secure Boot, first boot, the root partition grown and
# writable, the EFI partition mounted and kept current, core services,
# Docker, the device identity, and less in an SSH terminal (issue #6). Writes
# serial.log, report.txt and identity.txt to <out-dir>; exits non-zero if a
# check fails. Needs qemu-system-x86_64, ovmf, mtools, zstd, sshpass, expect,
# openssl, jq, curl. Uses KVM when /dev/kvm is writable.
#
# Kura Desktop is checked on 443 unless KURA_TEST_DESKTOP=false, which also
# puts "desktop": false in the setup file and checks that it is off.
# KURA_TEST_SCREENSHOTS=1 also signs in with a browser (Playwright's Chromium,
# installed for desktop/web) and saves signin.png and desktop.png.

set -euo pipefail

USAGE="Usage: $0 <pc-image> <out-dir> [ssh-port] [--setup|--installed]"
IMAGE="${1:?${USAGE}}"
OUT="${2:?${USAGE}}"
SSH_PORT="${3:-2222}"
# Kura Desktop's 443, forwarded beside SSH (by default 2222 -> 4222)
HTTPS_PORT="${KURA_TEST_HTTPS_PORT:-$(( SSH_PORT + 2000 ))}"
DESKTOP="${KURA_TEST_DESKTOP:-true}"
SETUP="${4:-}"
BRAND="${KURA_TEST_BRAND:-kura}"
LAYOUT="${KURA_TEST_LAYOUT:-server}"
LOGIN_USER="${KURA_TEST_USER:-admin}"
# The image's public default password, and the one-time password that
# replaces it at first boot, read from the console (default mode)
PUBLIC_DEFAULT_PASS="${KURA_TEST_PASS:-admin}"
ONE_TIME_PASS=""
# Set at first login (default mode), by the setup file (--setup), or given
# by KURA_TEST_LOGIN_PASS (--installed)
LOGIN_PASS="${KURA_TEST_LOGIN_PASS:-Kura-$(openssl rand -hex 8)}"

mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"
SERIAL="${OUT}/serial.log" REPORT="${OUT}/report.txt" IDENTITY="${OUT}/identity.txt"
PIDFILE="${OUT}/qemu.pid" DISK="${OUT}/disk.img" KEY="${OUT}/id_ed25519"
MONITOR="${OUT}/monitor.sock"
: > "${REPORT}"

MEM_MIB=4096
[ "${LAYOUT}" != full ] || MEM_MIB=2048

if [ -w /dev/kvm ]; then ACCEL=(-accel kvm -cpu host); WAIT_SECS=600
else ACCEL=(-accel tcg); WAIT_SECS=1500; fi

# Secure Boot firmware and variables with Microsoft's keys (Debian's shim is
# signed by Microsoft's UEFI CA), from the ovmf package
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.ms.fd
for f in "${OVMF_CODE}" "${OVMF_VARS}"; do
    [ -f "${f}" ] || { echo "ERROR: missing ${f} (install ovmf)" >&2; exit 2; }
done

stop_vm() { [ -f "${PIDFILE}" ] && kill "$(cat "${PIDFILE}")" 2>/dev/null; rm -f "${PIDFILE}"; }
trap stop_vm EXIT

# shellcheck source=tests/boot/boot-checks.sh
source "$(dirname "$0")/boot-checks.sh"
# shellcheck source=tests/boot/desktop-checks.sh
source "$(dirname "$0")/desktop-checks.sh"
# PC_EFI_START, where the setup file goes
# shellcheck source=scripts/x86_64/pc-image.sh
source "$(dirname "$0")/../../scripts/x86_64/pc-image.sh"

# ---- disk ----

case "${IMAGE}" in
    *.zst) zstd -q -d -f -o "${DISK}" "${IMAGE}" ;;
    *) cp "${IMAGE}" "${DISK}" ;;
esac
IMAGE_BYTES="${KURA_TEST_IMAGE_BYTES:-$(stat -c %s "${DISK}")}"
# room for the setup file's disk layout (sparse: costs nothing)
if [ "${LAYOUT}" = full ]; then truncate -s +14G "${DISK}"; else truncate -s +6G "${DISK}"; fi

if [ "${SETUP}" = "--setup" ]; then
    LOGIN_USER="${SETUP_USER}"
    make_setup_file "${OUT}/kura-setup.json"
    mcopy -o -i "${DISK}@@$(( PC_EFI_START * 512 ))" "${OUT}/kura-setup.json" ::/kura-setup.json
elif [ "${SETUP}" = "--installed" ]; then
    LOGIN_USER="${SETUP_USER}"
    [ -n "${KURA_TEST_LOGIN_PASS:-}" ] && [ -f "${KEY}" ] ||
        { echo "ERROR: --installed needs KURA_TEST_LOGIN_PASS and ${KEY}" >&2; exit 2; }
fi

# ---- boot ----

cp "${OVMF_VARS}" "${OUT}/ovmf-vars.fd"
report "Booting ${IMAGE} ${SETUP} ${LAYOUT} layout (UEFI Secure Boot, ${ACCEL[*]}, wait ${WAIT_SECS}s, no internet)"
qemu-system-x86_64 -machine q35,smm=on -m "${MEM_MIB}" -smp 2 "${ACCEL[@]}" \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${OUT}/ovmf-vars.fd" \
    -drive "file=${DISK},format=raw,if=virtio" \
    -vga none -device VGA,xres=1920,yres=1080 \
    -display none -monitor "unix:${MONITOR},server,nowait" -serial "file:${SERIAL}" \
    -nic "user,restrict=on,hostfwd=tcp::${SSH_PORT}-:22,hostfwd=tcp::${HTTPS_PORT}-:443" \
    -pidfile "${PIDFILE}" -daemonize

# ---- checks ----

# sshd starts after first boot: its marker is checked once logged in
splash_screens 40 &
SPLASH_PID=$!
check "SSH reachable" wait_for "SSH" ssh_listening
kill "${SPLASH_PID}" 2>/dev/null || true
if [ -n "${SETUP}" ]; then
    check "setup: SSH key login as the new user" wait_for "key login" ssh_run true
    check "setup: password logins refused" password_login_refused
    check "setup: hostname, Wi-Fi, time zone applied" setup_applied
    check "setup: file deleted from the EFI partition" setup_file_gone
    check "setup: disk layout built" layout_built
else
    check "one-time password on the login screen" wait_for "one-time password" console_password
    check "first login replaces the one-time password" first_login_changes_password
fi
check "Kura registered as a package" kura_package
check "first boot finished" ssh_run "test -f /var/lib/${BRAND}/.firstboot-done"
check "root partition grown and writable" root_grown "${IMAGE_BYTES}"
check "core services active" services_active
check "Docker answers" docker_answers
# Kura Desktop (ADR-023)
if [ "${DESKTOP}" = false ]; then
    check "desktop: off as the setup file asked, nothing on 443" desktop_off
else
    check "desktop: HTTPS on 443 serves the interface" wait_for "desktop" desktop_https
    check "desktop: the certificate served is the device's own" desktop_cert_matches
    check "desktop: the login screen shows its fingerprint" wait_for "fingerprint on the login screen" desktop_cert_shown
    check "desktop: signs in with the login user's password" desktop_signin
    check "desktop: a wrong password is refused" desktop_wrong_password_refused
    check "desktop: a request without X-Kura-Request is refused" desktop_csrf_refused
    check "desktop: server under 40 MB resident" desktop_rss
    [ "${KURA_TEST_SCREENSHOTS:-}" != 1 ] ||
        check "desktop: sign-in and desktop screenshots (signin.png, desktop.png)" desktop_screens
fi
if [ -n "${SETUP}" ]; then
    check "login screen says the setup was applied" wait_for "kura-issue" setup_shown
fi
# the rest does not depend on the disk layout: a full-layout boot skips it
if [ "${LAYOUT}" != full ]; then
    check "Secure Boot on" secure_boot_on
    check "EFI partition mounted and kept current" efi_partition_current
    check "device identity recorded" record_identity
    check "less works in an SSH terminal" less_works
    check "splash: kura is the default theme" splash_theme_default
    check "splash: theme in the initrd that boots" splash_in_initrd
    check "GRUB menu in Kura's colours" grub_themed
    check "console font is Terminus 16x32" console_font
    check "login screen has the Kura look (login.png)" login_screen
fi
[ -z "${SETUP}" ] || check "setup: disk layout back after a restart" layout_after_restart
# Last: a failed login counts against this source in sshd's penalties
[ -n "${SETUP}" ] || check "the public default password is refused" default_password_refused

if [ "${FAILED}" -ne 0 ]; then
    collect_diagnostics
    report "RESULT: FAILED"
    exit 1
fi
report "RESULT: PASSED"
