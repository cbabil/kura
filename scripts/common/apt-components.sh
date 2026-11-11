#!/bin/bash
# scripts/common/apt-components.sh
# APT source changes shared by the targets' configure-repos.sh and the
# Docker repo: components, pinned signing keys, the rootfs's codename.
# Source this file; it defines functions only.

# add_non_free_firmware <rootfs>: Debian's non-free-firmware component, for
# Wi-Fi, GPU and CPU firmware. Handles DEB822 .sources and sources.list.
add_non_free_firmware() {
    local rootfs="$1"
    if [ -f "${rootfs}/etc/apt/sources.list.d/debian.sources" ]; then
        sed -i.orig 's|^Components: main$|Components: main non-free-firmware|' \
            "${rootfs}/etc/apt/sources.list.d/debian.sources"
        rm -f "${rootfs}/etc/apt/sources.list.d/debian.sources.orig"
    elif [ -f "${rootfs}/etc/apt/sources.list" ]; then
        sed -i.orig 's|^\(deb .* trixie main\)$|\1 non-free-firmware|' "${rootfs}/etc/apt/sources.list"
        rm -f "${rootfs}/etc/apt/sources.list.orig"
    fi
}

DEBIAN_SECURITY_URL="https://security.debian.org/debian-security"

# add_debian_updates <rootfs>: Debian's <codename>-updates and
# <codename>-security suites next to the main one, with its components and
# key (the bootstrap writes only the main suite, which gets no security
# fixes between point releases). Handles DEB822 .sources and sources.list;
# running it again changes nothing.
add_debian_updates() {
    local rootfs="$1" c f line
    c=$(rootfs_codename "${rootfs}") || return 1
    f="${rootfs}/etc/apt/sources.list.d/debian.sources"
    if [ -f "${f}" ]; then
        grep -q "^Suites: ${c}-security$" "${f}" && return 0
        sed -i.orig "s|^Suites: ${c}\$|Suites: ${c} ${c}-updates|" "${f}" && rm -f "${f}.orig"
        local stanza
        stanza=$(grep -m1 '^Types:' "${f}"
            echo "URIs: ${DEBIAN_SECURITY_URL}"
            echo "Suites: ${c}-security"
            grep -m1 '^Components:' "${f}"
            grep -m1 '^Signed-By:' "${f}" || true)
        printf '\n%s\n' "${stanza}" >> "${f}"
        return 0
    fi
    f="${rootfs}/etc/apt/sources.list"
    [ -f "${f}" ] || return 1
    grep -q " ${c}-security " "${f}" && return 0
    line=$(grep -m1 -E "^deb (\[[^]]*\] )?[^ ]+ ${c} " "${f}") || return 1
    # deb [opts] <uri> <codename> <components>
    printf '%s\n' "${line/ ${c} / ${c}-updates }" >> "${f}"
    sed -E "s|^(deb (\[[^]]*\] )?)[^ ]+ ${c} |\1${DEBIAN_SECURITY_URL} ${c}-security |" <<< "${line}" >> "${f}"
}

# pinned_key <key-file> <fingerprint> <out-file>
# Writes only the key with <fingerprint>, armored. Fails if the file doesn't
# contain it, so extra keys in a download are never trusted by apt. Uses a
# throwaway GNUPGHOME so the build user's keyring is never touched.
pinned_key() {
    local key="$1" fpr="$2" out="$3" home status=0
    if ! command -v gpg >/dev/null 2>&1; then
        echo "ERROR: gpg is required to verify APT signing keys" >&2
        return 1
    fi
    home=$(mktemp -d)
    if ! GNUPGHOME="${home}" gpg --batch --quiet --import "${key}" 2>/dev/null; then
        echo "ERROR: could not read a key from ${key}" >&2
        status=1
    elif ! GNUPGHOME="${home}" gpg --batch --list-keys "${fpr}" >/dev/null 2>&1; then
        echo "ERROR: GPG key fingerprint mismatch: pinned key ${fpr} not in ${key}" >&2
        status=1
    else
        GNUPGHOME="${home}" gpg --batch --armor --export "${fpr}" > "${out}"
    fi
    rm -rf "${home}"
    return "${status}"
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
