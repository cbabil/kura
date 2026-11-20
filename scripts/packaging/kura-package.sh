#!/bin/bash
# scripts/packaging/kura-package.sh
# Kura's own parts as one Debian package per image (ADR-025): `kura`, amd64
# for the PC image and arm64 for the Pi's. It is staged from the finished
# rootfs, so the image and a device upgraded with apt hold the same files,
# then installed into that rootfs, so dpkg knows the image has it.
#
# In the package: Kura's programs, units and snippets. Not in it: what a
# device changes (config.json, brand.env, hardening.json, the sshd snippet,
# /etc/issue, fstab, the unit links). hardening.json ships as a default,
# and the Kura units the image enables as units.list; pkg-hooks.sh (run by
# the postinst) applies both on the device.
#
# Source this file; it defines functions only.

# kura_owned <rootfs> <brand>: the package's files, relative to the rootfs
kura_owned() {
    local b="$2"
    ( cd "$1" && find \
        "usr/bin/${b}-config" "usr/bin/${b}-security" "usr/lib/${b}" \
        usr/lib/systemd/system/"${b}"-*.service usr/lib/systemd/system/"${b}"-*.timer \
        usr/share/dbus-1/system.d/io.kura.Helper.conf \
        "usr/lib/sysusers.d/${b}-desktop.conf" "usr/lib/tmpfiles.d/${b}-desktop.conf" \
        etc/update-motd.d "etc/NetworkManager/conf.d/00-${b}-network.conf" "etc/profile.d/${b}.sh" \
        etc/apt/apt.conf.d/20auto-upgrades "etc/apt/apt.conf.d/52${b}-upgrades" \
        etc/apt/apt.conf.d/53"${b}"-*-upgrades "etc/apt/apt.conf.d/90${b}-efi" \
        "etc/kernel/postinst.d/zz-${b}-boot" \
        "usr/share/keyrings/${b}-archive.asc" "etc/apt/sources.list.d/${b}.sources" \
        "etc/apt/preferences.d/${b}-archive" \
        "usr/share/plymouth/themes/${b}" usr/share/grub/themes/kura \
        \( -type f -o -type l \) -print 2>/dev/null ) | sort
}

# kura_units <rootfs> <brand>: "<target> <unit>" for each Kura unit the image
# enables
kura_units() {
    local link
    for link in "$1"/etc/systemd/system/*.wants/"$2"-*; do
        [ -L "${link}" ] || continue
        echo "$(basename "$(dirname "${link}")" .wants) $(basename "${link}")"
    done
}

# stage_kura_package <rootfs> <brand> <version> <arch> <stage-dir>
stage_kura_package() {
    local rootfs="$1" b="$2" version="$3" arch="$4" stage="$5" here f
    here="$(dirname "${BASH_SOURCE[0]}")"
    if ! [[ "${version}" =~ ^[0-9][A-Za-z0-9.+~-]*$ ]]; then
        echo "ERROR: '${version}' is not a Debian package version" >&2
        return 1
    fi
    rm -rf "${stage}"
    mkdir -p "${stage}/DEBIAN" "${stage}/usr/lib/${b}/defaults"
    while IFS= read -r f; do
        mkdir -p "${stage}/$(dirname "${f}")"
        cp -a "${rootfs}/${f}" "${stage}/${f}"
    done < <(kura_owned "${rootfs}" "${b}")
    if [ -f "${rootfs}/etc/${b}/security/hardening.json" ]; then
        install -m 0644 "${rootfs}/etc/${b}/security/hardening.json" "${stage}/usr/lib/${b}/defaults/hardening.json"
    fi
    kura_units "${rootfs}" "${b}" > "${stage}/usr/lib/${b}/units.list"
    cat > "${stage}/DEBIAN/control" <<CONTROL
Package: ${b}
Version: ${version}
Architecture: ${arch}
Maintainer: Kura (https://github.com/cbabil/kura)
Section: admin
Priority: optional
Depends: bash, jq, systemd
Description: Kura's own programs, units and settings
 The parts of the Kura home-server OS that Debian's packages do not
 provide. Installing a newer version moves the device to that Kura version.
CONTROL
    sed "s|__BRAND__|${b}|g" "${here}/postinst" > "${stage}/DEBIAN/postinst"
    chmod 0755 "${stage}/DEBIAN/postinst"
}

# build_kura_package <rootfs> <brand> <version> <arch> <out-dir>: the .deb,
# whose path is printed
build_kura_package() {
    local stage deb="$5/$2_$3_$4.deb"
    stage=$(mktemp -d) || return 1
    stage_kura_package "$1" "$2" "$3" "$4" "${stage}/pkg" &&
    mkdir -p "$5" &&
    dpkg-deb --root-owner-group -Zxz --build "${stage}/pkg" "${deb}" >/dev/null || { rm -rf "${stage}"; return 1; }
    rm -rf "${stage}"
    echo "${deb}"
}
