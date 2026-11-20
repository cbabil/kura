#!/bin/bash
# scripts/common/kura-repo.sh
# Kura's own apt repository on a device (ADR-025): the assets of the latest
# GitHub release, laid out as a flat repository (scripts/release/
# make-apt-repo.sh), signed with the Kura Archive key pinned below. The key
# is kept in config/keys/, so builds never download one; its private half
# signs in release.yml only. The repository is not one of the automatic
# updates' origins: a new Kura version is installed when the owner asks
# (sudo apt full-upgrade).
#
# Source this file; it defines functions only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/apt-components.sh"

KURA_KEY_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/keys/kura-archive.asc"
KURA_GPG_FINGERPRINT="BEDAAE58BB6B8D7A6221435194D0EA5CB90A6B6E"

# install_kura_repo <rootfs> <brand> <owner/repo>: the pinned key and the
# source (both in the kura package, which can change them later)
install_kura_repo() {
    local rootfs="$1" b="$2" tmp status=0
    local keyring="usr/share/keyrings/${b}-archive.asc"
    tmp=$(mktemp)
    if pinned_key "${KURA_KEY_FILE}" "${KURA_GPG_FINGERPRINT}" "${tmp}"; then
        install -d -m 0755 "${rootfs}/usr/share/keyrings" "${rootfs}/etc/apt/sources.list.d"
        install -m 0644 "${tmp}" "${rootfs}/${keyring}"
        cat > "${rootfs}/etc/apt/sources.list.d/${b}.sources" <<SOURCE
Types: deb
URIs: ${KURA_REPO_URL:-https://github.com/$3/releases/latest/download/}
Suites: ./
Signed-By: /${keyring}
SOURCE
        # The repository's key can vouch for the kura package only: any other
        # package it lists (one of Debian's names, say) is never installed
        install -d -m 0755 "${rootfs}/etc/apt/preferences.d"
        cat > "${rootfs}/etc/apt/preferences.d/${b}-archive" <<PREFERENCES
# ${b}: its repository supplies the ${b} package and nothing else
Package: *
Pin: release o=Kura
Pin-Priority: -1

Package: ${b}
Pin: release o=Kura
Pin-Priority: 500
PREFERENCES
    else
        status=1
    fi
    rm -f "${tmp}"
    return "${status}"
}
