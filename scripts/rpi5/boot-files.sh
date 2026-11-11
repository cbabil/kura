#!/bin/bash
# scripts/rpi5/boot-files.sh
# The Pi boots the kernel, device tree and overlays on its FAT boot partition
# (config.txt: kernel=vmlinuz). The build copies them there (create-image.sh),
# and on the device a kernel hook (install_pi_boot_hook) copies every new
# kernel there, so kernel security updates reach the running Pi. The boot
# partition is mounted only for that copy, as for first boot.
#
# Installed to /usr/lib/<brand>/ next to firstboot-disk.sh (boot_partition,
# is_fat_partition, with_mount). Source this file; it defines functions only.

PI_DTB="bcm2712-rpi-5-b.dtb"
# Debian's raspi-firmware hooks write /boot/firmware, which Kura never
# mounts: on a Pi they fail every kernel upgrade, and they would replace
# Kura's config.txt
RASPI_FIRMWARE_HOOKS=(/etc/kernel/postinst.d/z50-raspi-firmware /etc/kernel/postrm.d/z50-raspi-firmware
    /etc/initramfs/post-update.d/z50-raspi-firmware)

# newest_kernel <root>: the newest /boot/vmlinuz-<version>, by version
newest_kernel() {
    local k
    k=$(find "$1/boot" -maxdepth 1 -name 'vmlinuz-*' ! -name '*.dpkg-*' ! -name '*.old-dkms' 2>/dev/null |
        sort -V | tail -1)
    [ -n "${k}" ] && echo "${k}"
}

# first_existing <paths...>: the first that exists
first_existing() {
    local p
    for p in "$@"; do [ -e "${p}" ] && { echo "${p}"; return 0; }; done
    return 1
}

# copy_atomic <src> <dst>: written beside <dst>, then renamed over it
copy_atomic() { cp "$1" "$2.new" && mv "$2.new" "$2"; }

# copy_kernel_files <root> <boot-dir>: the newest kernel as vmlinuz, its
# device tree and overlays. Each file is written beside its target, then
# renamed over it.
copy_kernel_files() {
    local root="$1" boot="$2" kernel v dtb overlays
    kernel=$(newest_kernel "${root}") || { echo "ERROR: no kernel in ${root}/boot" >&2; return 1; }
    v="${kernel##*/vmlinuz-}"
    copy_atomic "${kernel}" "${boot}/vmlinuz" || return 1
    if dtb=$(first_existing "${root}/usr/lib/linux-image-${v}/broadcom/${PI_DTB}" \
            "${root}/boot/dtbs/${v}/broadcom/${PI_DTB}" "${root}/boot/broadcom/${PI_DTB}" "${root}/boot/${PI_DTB}"); then
        copy_atomic "${dtb}" "${boot}/${PI_DTB}" || return 1
    else
        echo "WARNING: ${PI_DTB} not found for ${v}" >&2
    fi
    if overlays=$(first_existing "${root}/usr/lib/linux-image-${v}/overlays" \
            "${root}/boot/dtbs/${v}/overlays" "${root}/boot/overlays"); then
        rm -rf "${boot}/overlays.new" && cp -r "${overlays}" "${boot}/overlays.new" &&
            rm -rf "${boot}/overlays" && mv "${boot}/overlays.new" "${boot}/overlays" || return 1
    fi
    sync
    echo "Pi boot partition: kernel ${v}"
}

# copy_running_kernel <mounted-boot-dir>: copy_kernel_files from this system
copy_running_kernel() { copy_kernel_files "" "$1"; }

# update_pi_boot: the kernel hook's work. Nothing in a chroot (the build
# copies the files itself); on the device, only onto a FAT boot partition.
update_pi_boot() {
    local dev
    ! ischroot || return 0
    if ! dev=$(boot_partition) || ! is_fat_partition "${dev}"; then
        echo "ERROR: no FAT boot partition; the new kernel is not installed for boot" >&2
        return 1
    fi
    with_mount "${dev}" copy_running_kernel -t vfat -o nosuid,nodev,noexec,umask=077
}

# divert_raspi_firmware_hooks <rootfs>: set Debian's hooks aside for good
# (a diversion survives raspi-firmware upgrades)
divert_raspi_firmware_hooks() {
    local h
    for h in "${RASPI_FIRMWARE_HOOKS[@]}"; do
        chroot "$1" dpkg-divert --local --rename --divert "${h}.kura-disabled" --add "${h}" || return 1
    done
}

# install_pi_boot_hook <rootfs> <brand>: these helpers, and the kernel hook
# that runs update_pi_boot after every kernel install
install_pi_boot_hook() {
    local rootfs="$1" brand="$2" lib="/usr/lib/$2"
    install -d "${rootfs}${lib}" "${rootfs}/etc/kernel/postinst.d"
    install -m 0644 "${BASH_SOURCE[0]}" "${rootfs}${lib}/boot-files.sh"
    cat > "${rootfs}/etc/kernel/postinst.d/zz-${brand}-boot" <<EOF
#!/bin/bash
# Copies a new kernel onto the Pi's boot partition (${lib}/boot-files.sh)
source ${lib}/firstboot-disk.sh
source ${lib}/boot-files.sh
update_pi_boot
EOF
    chmod 0755 "${rootfs}/etc/kernel/postinst.d/zz-${brand}-boot"
}
