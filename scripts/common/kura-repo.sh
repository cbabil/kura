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

# Overridable: the upgrade test serves its own repository, with its own key
: "${KURA_KEY_FILE:=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/config/keys/kura-archive.asc}"
: "${KURA_GPG_FINGERPRINT:=BEDAAE58BB6B8D7A6221435194D0EA5CB90A6B6E}"

# install_kura_repo <rootfs> <brand> <owner/repo>: the pinned key and the
# source (both in the kura package, which can change them later)
install_kura_repo() {
    local rootfs="$1" b="$2" tmp
    local keyring="usr/share/keyrings/${b}-archive.asc"
    tmp=$(mktemp)
    pinned_key "${KURA_KEY_FILE}" "${KURA_GPG_FINGERPRINT}" "${tmp}" || { rm -f "${tmp}"; return 1; }
    install -d -m 0755 "${rootfs}/usr/share/keyrings" "${rootfs}/etc/apt/sources.list.d" \
        "${rootfs}/etc/apt/preferences.d"
    install -m 0644 "${tmp}" "${rootfs}/${keyring}"
    rm -f "${tmp}"
    cat > "${rootfs}/etc/apt/sources.list.d/${b}.sources" <<SOURCE
Types: deb
URIs: ${KURA_REPO_URL:-https://github.com/$3/releases/latest/download/}
Suites: ./
Signed-By: /${keyring}
SOURCE
    # Only the ${b} package is taken from this repository: a mistake in a
    # release (a stray package under one of Debian's names) is never
    # installed. Not a defence against the key's holder, whose ${b} package
    # runs as root anyway.
    cat > "${rootfs}/etc/apt/preferences.d/${b}-archive" <<PREFERENCES
# ${b}: its repository supplies the ${b} package and nothing else
Package: *
Pin: release o=Kura
Pin-Priority: -1

Package: ${b}
Pin: release o=Kura
Pin-Priority: 500
PREFERENCES
}
