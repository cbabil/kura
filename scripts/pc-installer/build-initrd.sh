#!/bin/bash
# scripts/pc-installer/build-initrd.sh
# Build the PC installer's initrd (ADR-017) from a rootfs holding the
# packages of config/packages-pc-installer.list: busybox for the basics, the
# few dynamic tools the installer needs with their libraries, the kernel
# modules of modules.list with their dependencies, Realtek NIC firmware, CA
# certificates, the Terminus 16x32 console font, and the installer scripts. The tree is assembled inside the
# rootfs (/tmp/initrd) so ldd, modprobe and depmod run in a chroot.
#
# Usage: build-initrd.sh <rootfs> <kernel-version> <output-initrd>
# Requires: chroot (root required)

set -euo pipefail

USAGE="Usage: $0 <rootfs> <kernel-version> <output-initrd>"
ROOTFS="${1:?${USAGE}}"
KVER="${2:?${USAGE}}"
OUTPUT="${3:?${USAGE}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# shellcheck disable=SC1091
source "${SCRIPT_DIR}/../common/brand-defaults.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/installer-image.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
LIB_DIR="usr/lib/${BRAND}-installer"
# Dynamic tools; busybox provides everything else
TOOLS=(/usr/bin/bash /usr/bin/curl /usr/bin/zstd /usr/bin/jq /usr/sbin/sfdisk /usr/bin/kmod)
TREE="${ROOTFS}/tmp/initrd"

rm -rf "${TREE}"
mkdir -p "${TREE}"/usr/{bin,sbin,lib,lib64} "${TREE}"/{etc/ssl/certs,dev,proc,sys,run,tmp}
for dir in bin sbin lib lib64; do ln -s "usr/${dir}" "${TREE}/${dir}"; done

# copy_from_rootfs <path>: same path in the tree, symlinks followed
copy_from_rootfs() {
    mkdir -p "${TREE}$(dirname "$1")"
    cp -L "${ROOTFS}$1" "${TREE}$1"
}

echo "  Tools and libraries..."
copy_from_rootfs /usr/bin/busybox
for tool in "${TOOLS[@]}"; do
    copy_from_rootfs "${tool}"
    while read -r lib; do
        copy_from_rootfs "${lib}"
    done < <(chroot "${ROOTFS}" ldd "${tool}" | ldd_paths)
done
ln -s kmod "${TREE}/usr/bin/modprobe"
copy_from_rootfs /etc/ssl/certs/ca-certificates.crt
printf 'hosts: files dns\n' > "${TREE}/etc/nsswitch.conf"
printf '127.0.0.1 localhost\n' > "${TREE}/etc/hosts"

echo "  Kernel modules (${KVER})..."
while read -r module; do
    case "${module}" in ''|'#'*) continue ;; esac
    deps=$(chroot "${ROOTFS}" modprobe -S "${KVER}" --show-depends "${module}" 2>/dev/null) ||
        { echo "    (no module ${module}, skipped)"; continue; }
    while read -r file; do
        copy_from_rootfs "${file}"
    done < <(module_paths <<< "${deps}")
done < "${SCRIPT_DIR}/modules.list"
for meta in modules.order modules.builtin modules.builtin.modinfo; do
    copy_from_rootfs "/usr/lib/modules/${KVER}/${meta}"
done
chroot "${ROOTFS}" depmod -b /tmp/initrd "${KVER}"
if [ -d "${ROOTFS}/usr/lib/firmware/rtl_nic" ]; then
    mkdir -p "${TREE}/usr/lib/firmware"
    cp -r "${ROOTFS}/usr/lib/firmware/rtl_nic" "${TREE}/usr/lib/firmware/"
fi

echo "  Installer..."
mkdir -p "${TREE}/${LIB_DIR}"
cp "${SCRIPT_DIR}/install.sh" "${SCRIPT_DIR}/run.sh" "${SCRIPT_DIR}/screen.sh" "${SCRIPT_DIR}/ui.sh" \
    "${SCRIPT_DIR}/udhcpc.script" "${SCRIPT_DIR}/modules.list" \
    "${SCRIPT_DIR}/../common/firstboot-disk.sh" "${TREE}/${LIB_DIR}/"
# 16x32 cells: 120x33 on a 1920x1080 screen; busybox setfont wants it unpacked
gzip -dc "${ROOTFS}/usr/share/consolefonts/Uni3-Terminus32x16.psf.gz" > "${TREE}/${LIB_DIR}/font.psf"
chmod 755 "${TREE}/${LIB_DIR}/udhcpc.script"
sed -e "s|__BRAND__|${BRAND}|g" -e "s|__BRAND_NAME__|${OS_NAME}|g" \
    -e "s|__LABEL__|${INSTALLER_LABEL}|g" "${SCRIPT_DIR}/init" > "${TREE}/init"
chmod 755 "${TREE}/init"

# The tree must run what init and install.sh call
echo "  Checking the tree..."
applets=$(chroot "${TREE}" /usr/bin/busybox --list)
for applet in mount umount findfs seq sleep ip udhcpc mkfifo mktemp tee sha256sum head cut \
        blockdev readlink basename ls wc dd grep cat cp rm rmdir mkdir sync ln tr poweroff setfont; do
    grep -qx "${applet}" <<< "${applets}" || { echo "ERROR: busybox lacks ${applet}" >&2; exit 1; }
done
for tool in "${TOOLS[@]}"; do
    chroot "${TREE}" "${tool}" --version >/dev/null 2>&1 ||
        { echo "ERROR: ${tool} does not run in the initrd" >&2; exit 1; }
done
chroot "${TREE}" /usr/bin/modprobe -S "${KVER}" --show-depends nvme >/dev/null ||
    { echo "ERROR: modprobe cannot resolve modules in the initrd" >&2; exit 1; }

echo "  Packing..."
chroot "${ROOTFS}" sh -c 'cd /tmp/initrd && find . | cpio -o -H newc --quiet | zstd -q -19 -T0' > "${OUTPUT}"
rm -rf "${TREE}"
echo "  Initrd: $(du -h "${OUTPUT}" | cut -f1)"
