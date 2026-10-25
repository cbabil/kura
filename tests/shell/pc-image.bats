#!/usr/bin/env bats
# tests/shell/pc-image.bats — the x86 PC disk image (target pc): GPT with an
# EFI partition (Debian's signed shim + GRUB, so Secure Boot works) and an
# ext4 root, built for real hardware such as the Intel NUC.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/x86_64/pc-image.sh"
}

@test "pc_partition_table: GPT, EFI system partition first, Linux root second" {
    run pc_partition_table 256
    [ "$status" -eq 0 ]
    file_has <(echo "$output") "label: gpt"
    file_has <(echo "$output") "start=${PC_EFI_START}, size=524288, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
    file_has <(echo "$output") "start=$(( PC_EFI_START + 524288 )), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4"
}

@test "pc_grub_cfg: boots Debian's kernel symlinks, so kernel updates take effect" {
    run pc_grub_cfg 1111-uuid 2222-partuuid Kura
    [ "$status" -eq 0 ]
    file_has <(echo "$output") "search --no-floppy --fs-uuid --set=root 1111-uuid"
    file_has <(echo "$output") "linux /vmlinuz root=PARTUUID=2222-partuuid ro"
    file_has <(echo "$output") "initrd /initrd.img"
    file_has <(echo "$output") 'menuentry "Kura"'
    # the kernel before the last upgrade, if the new one fails
    file_has <(echo "$output") "linux /vmlinuz.old root=PARTUUID=2222-partuuid ro"
    file_has <(echo "$output") "initrd /initrd.img.old"
}

@test "pc_grub_cfg: the screen is the main console (rescue prompts appear there)" {
    run pc_grub_cfg 1111-uuid 2222-partuuid Kura
    file_has <(echo "$output") "console=ttyS0,115200 console=tty0"
}

@test "pc_fstab: root checked at boot and remounted read-only on errors; EFI partition private" {
    run pc_fstab 2222-partuuid 3333-partuuid
    [ "$status" -eq 0 ]
    file_has <(echo "$output") "PARTUUID=2222-partuuid / ext4 errors=remount-ro 0 1"
    file_has <(echo "$output") "PARTUUID=3333-partuuid /boot/efi vfat umask=0077,nofail 0 2"
}

@test "pc_efi_files: Debian's signed GRUB, then shim at the removable boot path" {
    run pc_efi_files
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed EFI/BOOT/grubx64.efi" ]
    [ "${lines[1]}" = "usr/lib/shim/shimx64.efi.signed EFI/BOOT/BOOTX64.EFI" ]
    [ "${PC_GRUB_CFG}" = "EFI/debian/grub.cfg" ]
}

# ---- sync-efi: shim and GRUB updates reach the EFI partition ----

sync_root() {
    SYNC_ROOT="${BATS_TEST_TMPDIR}/sys"
    mkdir -p "${SYNC_ROOT}/usr/lib/shim" "${SYNC_ROOT}/usr/lib/grub/x86_64-efi-signed" \
             "${SYNC_ROOT}/boot/efi/EFI/BOOT"
    echo shim-2 > "${SYNC_ROOT}/usr/lib/shim/shimx64.efi.signed"
    echo grub-2 > "${SYNC_ROOT}/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed"
    echo shim-1 > "${SYNC_ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI"
    echo grub-2 > "${SYNC_ROOT}/boot/efi/EFI/BOOT/grubx64.efi"
    export SYNC_ROOT
}

@test "sync-efi: copies a newer shim or GRUB onto the mounted EFI partition" {
    sync_root
    mountpoint() { return 0; }
    export -f mountpoint
    run "${REPO_ROOT}/scripts/x86_64/sync-efi.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "${SYNC_ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI")" = "shim-2" ]
    [ "$(cat "${SYNC_ROOT}/boot/efi/EFI/BOOT/grubx64.efi")" = "grub-2" ]
    output_has "EFI/BOOT/BOOTX64.EFI"
    run grep -q "grubx64" <<< "$output"   # unchanged, so not copied
    [ "$status" -ne 0 ]
}

@test "sync-efi: does nothing when the EFI partition is not mounted" {
    sync_root
    mountpoint() { return 1; }
    export -f mountpoint
    run "${REPO_ROOT}/scripts/x86_64/sync-efi.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "${SYNC_ROOT}/boot/efi/EFI/BOOT/BOOTX64.EFI")" = "shim-1" ]
}

# ---- rootfs for real hardware ----

@test "packages-x86_64.list: signed boot chain, firmware and microcode" {
    local list="${REPO_ROOT}/config/packages-x86_64.list"
    for pkg in linux-image-amd64 shim-signed grub-efi-amd64-signed firmware-iwlwifi \
               firmware-realtek firmware-misc-nonfree intel-microcode amd64-microcode; do
        grep -qx "${pkg}" "${list}"
    done
}

@test "x86 configure-repos: adds non-free-firmware (DEB822 and sources.list)" {
    local rootfs="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${rootfs}/etc/apt/sources.list.d"
    printf 'Types: deb\nSuites: trixie\nComponents: main\n' > "${rootfs}/etc/apt/sources.list.d/debian.sources"
    run "${REPO_ROOT}/scripts/x86_64/configure-repos.sh" "${rootfs}"
    [ "$status" -eq 0 ]
    file_has "${rootfs}/etc/apt/sources.list.d/debian.sources" "Components: main non-free-firmware"
    rm "${rootfs}/etc/apt/sources.list.d/debian.sources"
    echo "deb http://deb.debian.org/debian trixie main" > "${rootfs}/etc/apt/sources.list"
    run "${REPO_ROOT}/scripts/x86_64/configure-repos.sh" "${rootfs}"
    file_has "${rootfs}/etc/apt/sources.list" "trixie main non-free-firmware"
}

@test "x86 customize-rootfs: installs the EFI sync run after every APT change" {
    local rootfs="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${rootfs}"
    run "${REPO_ROOT}/scripts/x86_64/customize-rootfs.sh" "${rootfs}"
    [ "$status" -eq 0 ]
    [ -x "${rootfs}/usr/lib/kura/sync-efi.sh" ]
    [ -f "${rootfs}/usr/lib/kura/efi-files.list" ]
    file_has "${rootfs}/etc/apt/apt.conf.d/90kura-efi" "DPkg::Post-Invoke"
    file_has "${rootfs}/etc/apt/apt.conf.d/90kura-efi" "/usr/lib/kura/sync-efi.sh"
}

@test "x86 customize-rootfs: the QEMU guest agent is left to start only in VMs" {
    local rootfs="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${rootfs}"
    run "${REPO_ROOT}/scripts/x86_64/customize-rootfs.sh" "${rootfs}"
    [ ! -L "${rootfs}/etc/systemd/system/multi-user.target.wants/qemu-guest-agent.service" ]
}

@test "x86 customize-rootfs: keeps firmware, drivers and time zones" {
    local rootfs="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${rootfs}/usr/lib/firmware/intel" "${rootfs}/usr/share/zoneinfo/Europe" \
             "${rootfs}/lib/modules/6.12.0-amd64/kernel/drivers/gpu"
    touch "${rootfs}/usr/lib/firmware/intel/ibt.sfi" "${rootfs}/usr/share/zoneinfo/Europe/Paris"
    run "${REPO_ROOT}/scripts/x86_64/customize-rootfs.sh" "${rootfs}"
    [ "$status" -eq 0 ]
    [ -f "${rootfs}/usr/lib/firmware/intel/ibt.sfi" ]
    [ -f "${rootfs}/usr/share/zoneinfo/Europe/Paris" ]
    [ -d "${rootfs}/lib/modules/6.12.0-amd64/kernel/drivers/gpu" ]
}
