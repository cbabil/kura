#!/bin/bash
# scripts/pc-installer/installer-image.sh
# Layout of the PC installer image (target pc-installer, ADR-017): GPT with a
# single FAT32 EFI partition holding the PC image's signed shim + GRUB, the
# signed Debian kernel and the installer's initrd. Partition 1 is where
# Etchwise puts kura-setup.json, as on the PC image. Also the parsers
# build-initrd.sh uses (ldd_paths, module_paths). Used by create-image.sh,
# build-initrd.sh and the boot tests. Defines functions and constants only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../x86_64/pc-image.sh"

# shellcheck disable=SC2034  # read by the scripts sourcing this
INSTALLER_LABEL="KURA-INST"

# installer_partition_table <efi-mib>: the PC image's table without its root
installer_partition_table() { pc_partition_table "$1" | grep -v 'name="root"'; }

# installer_files: "<file in the build rootfs> <file on the EFI partition>"
# lines: the PC image's shim + GRUB, then the kernel (initrd.img is built
# separately)
installer_files() {
    pc_efi_files
    echo "vmlinuz kura/vmlinuz"
}

# installer_grub_cfg <fs-label> <os-name> [kernel-args]: Debian's signed GRUB
# reads this from EFI/debian on the key and boots the installer from the same
# partition; the boot test adds kura.manifest=
installer_grub_cfg() {
    cat <<EOF
set timeout=3
set default=0
insmod part_gpt
insmod fat
search --no-floppy --label --set=root $1

menuentry "Install $2" {
    linux /kura/vmlinuz quiet ${PC_CONSOLE_ARGS}${3:+ $3}
    initrd /kura/initrd.img
}
EOF
}

# ldd_paths: the files an `ldd` listing (stdin) names, one per line
ldd_paths() { grep -o '/[^ ]*' || true; }

# module_paths: module files from `modprobe --show-depends` (stdin); built-in
# modules need no file
module_paths() { awk '$1 == "insmod" { print $2 }'; }
