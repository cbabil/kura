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
    file_has <(echo "$output") "start=2048, size=524288, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
    file_has <(echo "$output") "start=526336, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4"
}

@test "pc_grub_cfg: finds the root by UUID and boots it read-write by PARTUUID" {
    run pc_grub_cfg 1111-uuid 2222-partuuid vmlinuz-6.12.0-amd64 initrd.img-6.12.0-amd64 Kura
    [ "$status" -eq 0 ]
    file_has <(echo "$output") "search --no-floppy --fs-uuid --set=root 1111-uuid"
    file_has <(echo "$output") "linux /boot/vmlinuz-6.12.0-amd64 root=PARTUUID=2222-partuuid rw"
    file_has <(echo "$output") "initrd /boot/initrd.img-6.12.0-amd64"
    file_has <(echo "$output") 'menuentry "Kura"'
    run grep -q "boot=live\|toram" <<< "$output"
    [ "$status" -ne 0 ]
}

@test "pc_efi_files: Debian's signed shim as the removable boot path, signed GRUB next to it" {
    run pc_efi_files
    [ "$status" -eq 0 ]
    file_has <(echo "$output") "usr/lib/shim/shimx64.efi.signed EFI/BOOT/BOOTX64.EFI"
    file_has <(echo "$output") "usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed EFI/BOOT/grubx64.efi"
}

@test "pc_grub_cfg_path: where Debian's signed GRUB looks for its config" {
    [ "$(pc_grub_cfg_path)" = "EFI/debian/grub.cfg" ]
}

@test "the Pi image also mounts its root read-write (no fstab ships)" {
    file_has "${REPO_ROOT}/scripts/rpi5/cmdline.txt" "root=/dev/mmcblk0p2 rootfstype=ext4 rootwait rw"
}

# ---- rootfs for real hardware ----

@test "packages-x86_64.list: signed boot chain, firmware and microcode, no live boot" {
    local list="${REPO_ROOT}/config/packages-x86_64.list"
    for pkg in linux-image-amd64 shim-signed grub-efi-amd64-signed firmware-iwlwifi \
               firmware-realtek firmware-misc-nonfree intel-microcode amd64-microcode; do
        grep -qx "${pkg}" "${list}"
    done
    run grep -qx "live-boot" "${list}"
    [ "$status" -ne 0 ]
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

@test "x86 customize-rootfs: keeps firmware, drivers and time zones; no live-system mounts" {
    local rootfs="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${rootfs}/usr/lib/firmware/intel" "${rootfs}/usr/share/zoneinfo/Europe" \
             "${rootfs}/lib/modules/6.12.0-amd64/kernel/drivers/gpu"
    touch "${rootfs}/usr/lib/firmware/intel/ibt.sfi" "${rootfs}/usr/share/zoneinfo/Europe/Paris"
    run "${REPO_ROOT}/scripts/x86_64/customize-rootfs.sh" "${rootfs}"
    [ "$status" -eq 0 ]
    [ -f "${rootfs}/usr/lib/firmware/intel/ibt.sfi" ]
    [ -f "${rootfs}/usr/share/zoneinfo/Europe/Paris" ]
    [ -d "${rootfs}/lib/modules/6.12.0-amd64/kernel/drivers/gpu" ]
    [ ! -e "${rootfs}/usr/lib/systemd/system/var-lib-docker.mount" ]
}
