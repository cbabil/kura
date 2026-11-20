#!/bin/bash
# tests/boot/upgrade-test.sh
# Upgrades the latest RELEASED Kura in place to the package just built
# (ADR-025), in QEMU under UEFI Secure Boot: the path an owner's device
# takes. The released PC image is downloaded and checked against its
# manifest, booted with a setup file (no disk layout), and given a
# repository served by this host: the new package under a higher version,
# signed with a throwaway key. A release that has no kura package yet (0.5.2)
# goes through kura-adopt.sh; a later one through apt, with its source
# pointed at the test repository.
#
# Checked after the upgrade and again after a restart: the package and the
# version shown, the owner's settings untouched, a unit the owner turned off
# still off, nothing left for apt to do, and the device back with its
# services.
#
# Usage: upgrade-test.sh <new-kura.deb> <out-dir> [ssh-port]
# Needs what boot-test.sh needs, plus dpkg-deb, dpkg-scanpackages, gpg, jq,
# curl, python3, and the internet for the released image.

set -euo pipefail

USAGE="Usage: $0 <new-kura.deb> <out-dir> [ssh-port]"
NEW_DEB="${1:?${USAGE}}"
OUT="${2:?${USAGE}}"
SSH_PORT="${3:-2226}"
HTTP_PORT=$(( SSH_PORT + 6000 ))
BRAND="${KURA_TEST_BRAND:-kura}"
RELEASES="${KURA_TEST_RELEASES:-https://github.com/cbabil/kura/releases/latest/download}"
TEST_VERSION="9999.0~upgrade.test"
LOGIN_PASS="Kura-$(openssl rand -hex 8)"
BOOT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="${BOOT_DIR}/../.."

mkdir -p "${OUT}"
OUT="$(cd "${OUT}" && pwd)"
# shellcheck disable=SC2034  # read by boot-checks.sh
SERIAL="${OUT}/serial.log" REPORT="${OUT}/report.txt" KEY="${OUT}/id_ed25519" MONITOR="${OUT}/monitor.sock"
PIDFILE="${OUT}/qemu.pid" DISK="${OUT}/disk.img"
: > "${REPORT}"
rm -f "${KEY}" "${KEY}.pub"

if [ -w /dev/kvm ]; then ACCEL=(-accel kvm -cpu host); WAIT_SECS=600
else ACCEL=(-accel tcg); WAIT_SECS=1500; fi
OVMF_CODE=/usr/share/OVMF/OVMF_CODE_4M.secboot.fd
OVMF_VARS=/usr/share/OVMF/OVMF_VARS_4M.ms.fd

# shellcheck source=tests/boot/boot-checks.sh
source "${BOOT_DIR}/boot-checks.sh"
# shellcheck source=scripts/x86_64/pc-image.sh
source "${REPO_DIR}/scripts/x86_64/pc-image.sh"
# shellcheck source=scripts/common/hash.sh
source "${REPO_DIR}/scripts/common/hash.sh"

GNUPGHOME=$(mktemp -d /tmp/kura-upg.XXXXXX)
export GNUPGHOME
HTTP_PID=""
cleanup() {
    [ -z "${HTTP_PID}" ] || kill "${HTTP_PID}" 2>/dev/null || true
    [ ! -f "${PIDFILE}" ] || kill "$(cat "${PIDFILE}")" 2>/dev/null || true
    gpgconf --kill all 2>/dev/null || true
    rm -rf "${GNUPGHOME}" "${DISK}"
}
trap cleanup EXIT

# ---- the released image ----

curl -fsSL -o "${OUT}/manifest.json" "${RELEASES}/manifest.json"
OLD_VERSION=$(jq -r .version "${OUT}/manifest.json")
curl -fsSL -o "${OUT}/old.img.zst" "$(jq -r .bundles.x86_64.url "${OUT}/manifest.json")"
[ "$(file_sha256 "${OUT}/old.img.zst")" = "$(jq -r .bundles.x86_64.sha256 "${OUT}/manifest.json")" ] ||
    { echo "ERROR: the released image does not match its manifest" >&2; exit 2; }
zstd -q -d -f --rm -o "${DISK}" "${OUT}/old.img.zst"
truncate -s +2G "${DISK}"

LOGIN_USER="${SETUP_USER}"
make_setup_file "${OUT}/setup-full.json"
jq 'del(.storage)' "${OUT}/setup-full.json" > "${OUT}/kura-setup.json"
mcopy -o -i "${DISK}@@$(( PC_EFI_START * 512 ))" "${OUT}/kura-setup.json" ::/kura-setup.json

# ---- the repository with the new package ----

SERVE="${OUT}/repo"
rm -rf "${SERVE}" "${OUT}/pkg"
mkdir -p "${SERVE}"
dpkg-deb -R "${NEW_DEB}" "${OUT}/pkg"
NEW_RELEASE=$(cat "${OUT}/pkg/usr/lib/${BRAND}/release")
ARCH=$(sed -n 's/^Architecture: //p' "${OUT}/pkg/DEBIAN/control")
sed -i "s/^Version: .*/Version: ${TEST_VERSION}/" "${OUT}/pkg/DEBIAN/control"
dpkg-deb --root-owner-group --build "${OUT}/pkg" "${SERVE}/${BRAND}_${TEST_VERSION}_${ARCH}.deb" >/dev/null
rm -rf "${OUT}/pkg"
gpg --batch --quiet --pinentry-mode loopback --passphrase '' --allow-freeform-uid \
    --quick-generate-key "Kura upgrade test" ed25519 sign 1d
TEST_FPR=$(gpg --batch --list-keys --with-colons | awk -F: '/^fpr/{print $10; exit}')
gpg --batch --armor --export "${TEST_FPR}" > "${OUT}/test-key.asc"
"${REPO_DIR}/scripts/release/make-apt-repo.sh" "${SERVE}" "${TEST_FPR}"
KURA_REPO_URL="http://10.0.2.2:${HTTP_PORT}/" KURA_KEY_FILE="${OUT}/test-key.asc" KURA_GPG_FINGERPRINT="${TEST_FPR}" \
    "${REPO_DIR}/scripts/release/make-adopt.sh" "${BRAND}" test/test > "${SERVE}/kura-adopt.sh"
python3 -m http.server "${HTTP_PORT}" --bind 127.0.0.1 --directory "${SERVE}" > "${OUT}/http.log" 2>&1 &
HTTP_PID=$!

# ---- boot the released version ----

cp "${OVMF_VARS}" "${OUT}/ovmf-vars.fd"
report "Upgrading Kura ${OLD_VERSION} to the new package (UEFI Secure Boot, ${ACCEL[*]}, wait ${WAIT_SECS}s)"
qemu-system-x86_64 -machine q35,smm=on -m 2048 -smp 2 "${ACCEL[@]}" \
    -global driver=cfi.pflash01,property=secure,value=on \
    -drive "if=pflash,format=raw,unit=0,readonly=on,file=${OVMF_CODE}" \
    -drive "if=pflash,format=raw,unit=1,file=${OUT}/ovmf-vars.fd" \
    -drive "file=${DISK},format=raw,if=virtio" \
    -vga none -device VGA,xres=1920,yres=1080 \
    -display none -monitor "unix:${MONITOR},server,nowait" -serial "file:${SERIAL}" \
    -nic "user,hostfwd=tcp::${SSH_PORT}-:22" \
    -pidfile "${PIDFILE}" -daemonize

# ---- on the device ----

# owner_state: what an upgrade must leave as the owner set it
owner_state() {
    sudo_run "sh -c 'hostname; sha256sum /etc/${BRAND}/config.json /etc/ssh/sshd_config.d/10-${BRAND}.conf \
        /etc/${BRAND}/brand.env /etc/fstab; systemctl is-enabled ${BRAND}-desktopd ssh;
        stat -c \"%u:%g %a %n\" / /etc /etc/apt /etc/apt/sources.list.d /etc/apt/preferences.d /usr /usr/share \
            /usr/share/keyrings'" 2>&1
}

# upgrade: adopt a release without the package, else point its source at the
# test repository and let apt upgrade it
upgrade() {
    local url="http://10.0.2.2:${HTTP_PORT}/kura-adopt.sh"
    if ssh_run "dpkg-query -W -f='\${Status}' ${BRAND} 2>/dev/null" | grep -q "install ok installed"; then
        report "  path: apt (the release has the ${BRAND} package)"
        # the test repository in place of the release's, with the adopt script's own steps
        sudo_run "bash -c 'curl -fsSL ${url} > /run/adopt.sh && ADOPT_SOURCED=1 . /run/adopt.sh &&
            adopt_files && adopt_refresh &&
            DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade ${BRAND}'"
    else
        report "  path: kura-adopt.sh (the release has no ${BRAND} package)"
        sudo_run "bash -c 'curl -fsSL ${url} | bash'"
    fi >> "${OUT}/upgrade.log" 2>&1
}

# upgraded: the package at the test version, the new version shown, the
# automatic restart off, and nothing left for apt to do
upgraded() {
    local facts
    facts=$(ssh_run "dpkg-query -W -f='\${Status} \${Version}' ${BRAND}; echo
        cat /usr/lib/${BRAND}/release
        grep -c 'Automatic-Reboot \"false\"' /etc/apt/apt.conf.d/52${BRAND}-upgrades
        apt-cache policy ${BRAND} | grep -c 'Installed: ${TEST_VERSION}'")
    report_facts "${facts}"
    [ "${facts}" = "install ok installed ${TEST_VERSION}
${NEW_RELEASE}
1
1" ]
}

version_shown() { ssh_run "grep -qF '$(sed 's/.*"\(.*\)"/\1/' <<< "${NEW_RELEASE}")' /etc/issue"; }
owner_state_kept() { local now; now=$(owner_state); report_facts "${now}"; [ "${now}" = "${BEFORE}" ]; }
failed_units() { ssh_run "systemctl --failed --no-legend --plain | cut -d' ' -f1 | sort" || true; }
# no_new_failed_units: none that the released version did not already have
no_new_failed_units() {
    local now new
    now=$(failed_units)
    new=$(comm -13 <(echo "${FAILED_BEFORE}") <(echo "${now}"))
    report_facts "failed units before: ${FAILED_BEFORE:-none}; new: ${new:-none}"
    [ -z "${new}" ]
}

check "SSH reachable" wait_for "SSH" ssh_listening
check "the released version is set up" wait_for "first boot" ssh_run "test -f /var/lib/${BRAND}/.firstboot-done"
# the owner turns the Desktop off: an upgrade must not turn it back on
sudo_run "systemctl disable --now ${BRAND}-desktopd" >/dev/null 2>&1 || true
FAILED_BEFORE=$(failed_units)
BEFORE=$(owner_state)
report_facts "${BEFORE}"
check "upgrade runs" upgrade
check "package installed, new version, no restart by itself, apt satisfied" upgraded
check "the owner's settings and choices are unchanged" owner_state_kept
check "login screen shows the new version" wait_for "kura-issue" version_shown
check "back after a restart" restart_device
check "still upgraded after the restart" upgraded
check "the owner's settings and choices are unchanged after the restart" owner_state_kept
check "password logins still refused" password_login_refused
# first boot's own units, which the default list expects, are done by now
check "Docker, SSH and ${BRAND}-config active" services_active docker ssh "${BRAND}-config"
check "no unit failed that worked before" no_new_failed_units

if [ "${FAILED}" -ne 0 ]; then
    cat "${OUT}/upgrade.log" >> "${REPORT}" 2>/dev/null || true
    collect_diagnostics
    report "RESULT: FAILED"
    exit 1
fi
report "RESULT: PASSED"
