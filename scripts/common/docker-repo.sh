#!/bin/bash
# scripts/common/docker-repo.sh
# Helpers to add Docker's official APT repository to a target rootfs at
# build time, so docker-ce can be installed from the package list and every
# image boots with Docker already present (no network needed at first boot).
#
# The signing key is downloaded on the host and only the key matching a
# pinned fingerprint is given to apt inside the chroot.
#
# Source this file; it defines functions only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/apt-components.sh"

# shellcheck disable=SC2034
DOCKER_APT_URL="https://download.docker.com/linux/debian"
DOCKER_GPG_URL="${DOCKER_APT_URL}/gpg"
# Docker Release (CE deb) signing key
DOCKER_GPG_FINGERPRINT="9DC858229FC7DD38854AE2D88D81803C0EBFCD88"
DOCKER_KEYRING_PATH="etc/apt/keyrings/docker.asc"
DOCKER_SOURCE_PATH="etc/apt/sources.list.d/docker.list"

# pinned_docker_key <key-file> <out-file>: only Docker's pinned key (pinned_key)
pinned_docker_key() { pinned_key "$1" "${DOCKER_GPG_FINGERPRINT}" "$2"; }

# docker_apt_source_line <arch> <codename>
docker_apt_source_line() {
    echo "deb [arch=$1 signed-by=/${DOCKER_KEYRING_PATH}] ${DOCKER_APT_URL} $2 stable"
}

# install_docker_repo <rootfs-dir> <arch>
# Downloads + verifies the Docker key and writes the APT source into the rootfs.
install_docker_repo() {
    local rootfs="$1" arch="$2" codename tmp status=0
    codename=$(rootfs_codename "${rootfs}")
    if [ -z "${codename}" ]; then
        echo "ERROR: cannot determine Debian codename from ${rootfs}/etc/os-release" >&2
        return 1
    fi

    tmp=$(mktemp -d)
    if ! curl -fsSL --connect-timeout 10 --max-time 60 "${DOCKER_GPG_URL}" -o "${tmp}/key"; then
        echo "ERROR: failed to download Docker GPG key from ${DOCKER_GPG_URL}" >&2
        status=1
    elif pinned_docker_key "${tmp}/key" "${tmp}/pinned"; then
        install -d -m 0755 "${rootfs}/$(dirname "${DOCKER_KEYRING_PATH}")" \
            "${rootfs}/$(dirname "${DOCKER_SOURCE_PATH}")"
        install -m 0644 "${tmp}/pinned" "${rootfs}/${DOCKER_KEYRING_PATH}"
        docker_apt_source_line "${arch}" "${codename}" > "${rootfs}/${DOCKER_SOURCE_PATH}"
        echo "Docker APT repository added (${arch}, ${codename})."
    else
        status=1
    fi
    rm -rf "${tmp}"
    return "${status}"
}
