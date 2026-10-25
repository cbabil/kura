#!/bin/bash
# scripts/x86_64/pc-image.sh
# Layout of the x86 PC disk image (target pc): GPT with an EFI system
# partition holding Debian's signed shim + GRUB (Secure Boot works) and an
# ext4 root. UEFI only, booted through the removable-media path, so it needs
# no firmware boot entry. Used by create-image.sh and the boot test. Defines
# functions and constants only.

# shellcheck disable=SC2034  # PC_GRUB_CFG and PC_EFI_START are read by the scripts sourcing this
PC_EFI_START=2048                                     # sector of partition 1
PC_EFI_TYPE="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
PC_ROOT_TYPE="0FC63DAF-8483-4772-8E79-3D69D8477DE4"   # Linux filesystem
PC_GRUB_CFG="EFI/debian/grub.cfg"                     # Debian's signed GRUB has this prefix built in
PC_EFI_FILES="$(dirname "${BASH_SOURCE[0]}")/efi-files.list"

# pc_partition_table <efi-mib>: sfdisk script, 1 MiB aligned. Partition 1 is
# the EFI partition: first boot reads kura-setup.json from it.
pc_partition_table() {
    local efi_sectors=$(( $1 * 1024 * 1024 / 512 ))
    cat <<EOF
label: gpt
unit: sectors

start=${PC_EFI_START}, size=${efi_sectors}, type=${PC_EFI_TYPE}, name="EFI"
start=$(( PC_EFI_START + efi_sectors )), type=${PC_ROOT_TYPE}, name="root"
EOF
}

# pc_efi_files: "<file in the rootfs> <file on the EFI partition>" lines
pc_efi_files() { grep -v '^#' "${PC_EFI_FILES}"; }

# pc_grub_cfg <root-fs-uuid> <root-partuuid> <os-name>
# Boots /vmlinuz and /initrd.img, the symlinks Debian's kernel packages keep
# pointing at the newest kernel (and .old at the previous one), so kernel
# updates take effect. The screen (tty0, listed last) is the main console;
# ttyS0 serves VMs.
pc_grub_cfg() {
    local args="root=PARTUUID=$2 ro quiet console=ttyS0,115200 console=tty0"
    cat <<EOF
set timeout=3
set default=0
insmod part_gpt
insmod ext2
search --no-floppy --fs-uuid --set=root $1

menuentry "$3" {
    linux /vmlinuz ${args}
    initrd /initrd.img
}

menuentry "$3 (previous kernel)" {
    linux /vmlinuz.old ${args}
    initrd /initrd.img.old
}
EOF
}

# pc_fstab <root-partuuid> <efi-partuuid>: root checked at boot and remounted
# read-only on errors; the EFI partition private to root (setup file, sync-efi)
pc_fstab() {
    cat <<EOF
PARTUUID=$1 / ext4 errors=remount-ro 0 1
PARTUUID=$2 /boot/efi vfat umask=0077,nofail 0 2
EOF
}
