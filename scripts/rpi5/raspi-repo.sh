#!/bin/bash
# scripts/rpi5/raspi-repo.sh
# The Raspberry Pi APT repository (kernel and firmware for the Pi 5), checked
# with the archive key pinned below and fetched over HTTPS. The key is the
# one Raspberry Pi re-signed with SHA-512 bindings in June 2025
# (raspberrypi-archive-keyring 2025.1), which Debian's verifier accepts; it is
# kept in config/keys/ so builds never download a key.
#
# Source this file; it defines functions only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../common/apt-components.sh"

RASPI_KEY_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/keys/raspberrypi-archive.asc"
RASPI_GPG_FINGERPRINT="CF8A1AF502A2AA2D763BAE7E82B129927FA3303E"
RASPI_APT_URL="https://archive.raspberrypi.com/debian/"
RASPI_KEYRING_PATH="etc/apt/keyrings/raspberrypi-archive.asc"

# install_raspi_repo <rootfs>: the pinned key and the source list
install_raspi_repo() {
    local rootfs="$1" codename tmp status=0
    codename=$(rootfs_codename "${rootfs}")
    [ -n "${codename}" ] || { echo "ERROR: no Debian codename in ${rootfs}" >&2; return 1; }
    tmp=$(mktemp)
    if pinned_key "${RASPI_KEY_FILE}" "${RASPI_GPG_FINGERPRINT}" "${tmp}"; then
        install -d -m 0755 "${rootfs}/etc/apt/keyrings" "${rootfs}/etc/apt/sources.list.d"
        install -m 0644 "${tmp}" "${rootfs}/${RASPI_KEYRING_PATH}"
        echo "deb [signed-by=/${RASPI_KEYRING_PATH}] ${RASPI_APT_URL} ${codename} main" \
            > "${rootfs}/etc/apt/sources.list.d/raspi.list"
    else
        status=1
    fi
    rm -f "${tmp}"
    return "${status}"
}
