#!/usr/bin/env bats
# tests/shell/pi-boot.bats — the Pi boots the kernel on its FAT boot
# partition: the build copies it there (create-image.sh), and on the device
# a kernel hook copies every new kernel there (scripts/rpi5/boot-files.sh),
# so kernel security updates reach the running Pi.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/rpi5/boot-files.sh"
    ROOT="${BATS_TEST_TMPDIR}/root"
    BOOT="${BATS_TEST_TMPDIR}/boot"
    mkdir -p "${ROOT}/boot" "${BOOT}"
    for v in 6.12.9-rpi-2712 6.12.10-rpi-2712; do
        echo "kernel ${v}" > "${ROOT}/boot/vmlinuz-${v}"
        mkdir -p "${ROOT}/usr/lib/linux-image-${v}/broadcom" "${ROOT}/usr/lib/linux-image-${v}/overlays"
        echo "dtb ${v}" > "${ROOT}/usr/lib/linux-image-${v}/broadcom/bcm2712-rpi-5-b.dtb"
        echo "overlay ${v}" > "${ROOT}/usr/lib/linux-image-${v}/overlays/new-${v}.dtbo"
    done
    CALLS="${BATS_TEST_TMPDIR}/calls"; : > "${CALLS}"
}

@test "copy_kernel_files: the newest kernel by version, not by name order" {
    copy_kernel_files "${ROOT}" "${BOOT}"
    [ "$(cat "${BOOT}/vmlinuz")" = "kernel 6.12.10-rpi-2712" ]
    [ ! -e "${BOOT}/vmlinuz.new" ]
}

@test "copy_kernel_files: that kernel's device tree and overlays, old overlays gone" {
    mkdir -p "${BOOT}/overlays"; echo old > "${BOOT}/overlays/stale.dtbo"
    copy_kernel_files "${ROOT}" "${BOOT}"
    [ "$(cat "${BOOT}/bcm2712-rpi-5-b.dtb")" = "dtb 6.12.10-rpi-2712" ]
    [ -f "${BOOT}/overlays/new-6.12.10-rpi-2712.dtbo" ]
    [ ! -e "${BOOT}/overlays/stale.dtbo" ]
}

@test "copy_kernel_files: fails with no kernel, leaving the boot partition alone" {
    rm -f "${ROOT}"/boot/vmlinuz-*
    echo "current" > "${BOOT}/vmlinuz"
    run copy_kernel_files "${ROOT}" "${BOOT}"
    [ "$status" -ne 0 ]
    [ "$(cat "${BOOT}/vmlinuz")" = "current" ]
}

@test "update_pi_boot: in a chroot (the build) does nothing" {
    ischroot() { return 0; }
    with_mount() { log_call "with_mount $*"; }
    run update_pi_boot
    [ "$status" -eq 0 ]
    [ ! -s "${CALLS}" ]
}

@test "update_pi_boot: on the device mounts the FAT boot partition just for the copy" {
    ischroot() { return 1; }
    boot_partition() { echo /dev/mmcblk0p1; }
    is_fat_partition() { return 0; }
    with_mount() { log_call "with_mount $*"; }
    run update_pi_boot
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "with_mount /dev/mmcblk0p1 copy_running_kernel -t vfat"
}

@test "update_pi_boot: fails when the boot partition is not FAT (never writes elsewhere)" {
    ischroot() { return 1; }
    boot_partition() { echo /dev/sda1; }
    is_fat_partition() { return 1; }
    with_mount() { log_call "with_mount $*"; }
    run update_pi_boot
    [ "$status" -ne 0 ]
    [ ! -s "${CALLS}" ]
}

@test "divert_raspi_firmware_hooks: Debian's hooks, which write /boot/firmware, are set aside" {
    chroot() { shift; log_call "$*"; }
    divert_raspi_firmware_hooks "${ROOT}"
    for h in /etc/kernel/postinst.d/z50-raspi-firmware /etc/kernel/postrm.d/z50-raspi-firmware \
             /etc/initramfs/post-update.d/z50-raspi-firmware; do
        file_has "${CALLS}" "dpkg-divert --local --rename --divert ${h}.kura-disabled --add ${h}"
    done
}

@test "the image build and the Pi customization use these functions" {
    grep -q 'copy_kernel_files "${ROOTFS}" "${BOOT_MNT}"' "${REPO_ROOT}/scripts/rpi5/create-image.sh"
    grep -q 'divert_raspi_firmware_hooks "${ROOTFS}"' "${REPO_ROOT}/scripts/rpi5/customize-rootfs.sh"
    grep -q 'install_pi_boot_hook "${ROOTFS}" "${BRAND}"' "${REPO_ROOT}/scripts/rpi5/customize-rootfs.sh"
}

@test "install_pi_boot_hook: a kernel hook that runs update_pi_boot from the installed helpers" {
    install_pi_boot_hook "${ROOT}" kura
    local hook="${ROOT}/etc/kernel/postinst.d/zz-kura-boot"
    [ -x "${hook}" ]
    file_has "${hook}" "/usr/lib/kura/boot-files.sh"
    file_has "${hook}" "update_pi_boot"
    [ -f "${ROOT}/usr/lib/kura/boot-files.sh" ]
}
