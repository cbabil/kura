#!/bin/bash
# scripts/x86_64/pc-image.sh
# Layout of the x86 PC disk image (target pc): GPT with an EFI system
# partition holding Debian's signed shim + GRUB (Secure Boot works) and an
# ext4 root. UEFI only, booted through the removable-media path, so it needs
# no firmware boot entry. Used by create-image.sh. Defines functions only.

# Partition type GUIDs
PC_EFI_TYPE="C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
PC_ROOT_TYPE="0FC63DAF-8483-4772-8E79-3D69D8477DE4"   # Linux filesystem

# pc_partition_table <efi-mib>: sfdisk script, 1 MiB aligned. Partition 1 is
# the EFI partition: first boot reads kura-setup.json from it.
pc_partition_table() {
    local efi_sectors=$(( $1 * 1024 * 1024 / 512 ))
    cat <<EOF
label: gpt
unit: sectors

start=2048, size=${efi_sectors}, type=${PC_EFI_TYPE}, name="EFI"
start=$(( 2048 + efi_sectors )), type=${PC_ROOT_TYPE}, name="root"
EOF
}

# pc_efi_files: "<source in the rootfs> <destination on the EFI partition>".
# shim is signed by Microsoft's UEFI CA and loads grubx64.efi from its own
# directory; both come from the shim-signed and grub-efi-amd64-signed packages.
pc_efi_files() {
    cat <<EOF
usr/lib/shim/shimx64.efi.signed EFI/BOOT/BOOTX64.EFI
usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed EFI/BOOT/grubx64.efi
EOF
}

# pc_grub_cfg_path: Debian's signed GRUB has its prefix built in
pc_grub_cfg_path() { echo "EFI/debian/grub.cfg"; }

# pc_grub_cfg <root-fs-uuid> <root-partuuid> <kernel> <initrd> <os-name>
# Kernel and initrd stay in the root filesystem's /boot. The root is mounted
# read-write by the kernel: the image ships no /etc/fstab.
pc_grub_cfg() {
    local args="root=PARTUUID=$2 rw quiet console=tty0 console=ttyS0,115200"
    cat <<EOF
set timeout=3
set default=0
insmod part_gpt
insmod ext2
search --no-floppy --fs-uuid --set=root $1

menuentry "$5" {
    linux /boot/$3 ${args}
    initrd /boot/$4
}

menuentry "$5 (debug)" {
    linux /boot/$3 ${args/quiet/loglevel=7}
    initrd /boot/$4
}
EOF
}
