#!/bin/bash
# scripts/common/docker-repo.sh
# Helpers to add Docker's official APT repository to a target rootfs at
# build time, so docker-ce can be installed from the package list and the
# image boots with Docker already present (no network needed at first boot).
#
# The signing key is downloaded on the host and its fingerprint is checked
# against a pinned value before apt inside the chroot is allowed to trust it.
#
# Source this file; it defines functions only.

# shellcheck disable=SC2034
DOCKER_APT_URL="https://download.docker.com/linux/debian"
DOCKER_GPG_URL="${DOCKER_APT_URL}/gpg"
# Docker Release (CE deb) signing key — same pin as the x86_64 firstboot.
DOCKER_GPG_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
DOCKER_KEYRING_PATH="etc/apt/keyrings/docker.asc"
DOCKER_SOURCE_PATH="etc/apt/sources.list.d/docker.list"

# docker_key_fingerprint <key-file>
# Prints the primary key fingerprint of an armored key file (empty if unreadable).
# Uses a throwaway GNUPGHOME so the build user's keyring is never touched.
docker_key_fingerprint() {
    local key="$1" home fpr
    home=$(mktemp -d)
    fpr=$(GNUPGHOME="${home}" gpg --batch --show-keys --with-colons "${key}" 2>/dev/null \
        | awk -F: '/^fpr:/{print $10; exit}')
    rm -rf "${home}"
    echo "${fpr}"
}

# verify_docker_key <key-file>
# Returns 0 only if the key's fingerprint matches DOCKER_GPG_FINGERPRINT.
verify_docker_key() {
    local key="$1" actual
    if ! command -v gpg >/dev/null 2>&1; then
        echo "ERROR: gpg is required to verify the Docker signing key" >&2
        return 1
    fi
    actual=$(docker_key_fingerprint "${key}")
    if [ -z "${actual}" ]; then
        echo "ERROR: could not read a fingerprint from ${key}" >&2
        return 1
    fi
    if [ "${actual}" != "${DOCKER_GPG_FINGERPRINT}" ]; then
        echo "ERROR: Docker GPG key fingerprint mismatch: ${actual}" >&2
        return 1
    fi
}

# rootfs_codename <rootfs-dir>
# Prints VERSION_CODENAME from the rootfs os-release (parsed, not sourced).
rootfs_codename() {
    local rootfs="$1" file
    file="${rootfs}/etc/os-release"
    [ -f "${file}" ] || file="${rootfs}/usr/lib/os-release"
    [ -f "${file}" ] || return 1
    sed -n 's/^VERSION_CODENAME=//p' "${file}" | tr -d '"' | head -1
}

# docker_apt_source_line <arch> <codename>
docker_apt_source_line() {
    echo "deb [arch=$1 signed-by=/${DOCKER_KEYRING_PATH}] ${DOCKER_APT_URL} $2 stable"
}

# install_docker_repo <rootfs-dir> <arch>
# Downloads + verifies the Docker key and writes the APT source into the rootfs.
install_docker_repo() {
    local rootfs="$1" arch="$2" codename tmpkey
    codename=$(rootfs_codename "${rootfs}")
    if [ -z "${codename}" ]; then
        echo "ERROR: cannot determine Debian codename from ${rootfs}/etc/os-release" >&2
        return 1
    fi

    tmpkey=$(mktemp)
    if ! curl -fsSL --connect-timeout 10 --max-time 60 "${DOCKER_GPG_URL}" -o "${tmpkey}"; then
        echo "ERROR: failed to download Docker GPG key from ${DOCKER_GPG_URL}" >&2
        rm -f "${tmpkey}"
        return 1
    fi
    if ! verify_docker_key "${tmpkey}"; then
        rm -f "${tmpkey}"
        return 1
    fi

    install -d -m 0755 "${rootfs}/$(dirname "${DOCKER_KEYRING_PATH}")" \
        "${rootfs}/$(dirname "${DOCKER_SOURCE_PATH}")"
    install -m 0644 "${tmpkey}" "${rootfs}/${DOCKER_KEYRING_PATH}"
    rm -f "${tmpkey}"
    docker_apt_source_line "${arch}" "${codename}" > "${rootfs}/${DOCKER_SOURCE_PATH}"
    echo "Docker APT repository added (${arch}, ${codename})."
}
