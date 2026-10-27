#!/usr/bin/env bats
# tests/shell/pc-installer.bats — the PC installer (target pc-installer): a
# small USB image that boots into RAM, downloads the Kura PC image and writes
# it to the PC's internal disk (ADR-017).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/pc-installer/installer-image.sh"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/pc-installer/install.sh"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/hash.sh"
    SYS_BLOCK="${BATS_TEST_TMPDIR}/sys/block"
    DEV_DIR="${BATS_TEST_TMPDIR}/dev"
    KEY_DIR="${BATS_TEST_TMPDIR}/key"
    mkdir -p "${SYS_BLOCK}" "${DEV_DIR}" "${KEY_DIR}"
    CALLS="${BATS_TEST_TMPDIR}/calls"
}

# fake_disk <name> <bytes> [removable] [model]
fake_disk() {
    mkdir -p "${SYS_BLOCK}/$1/device"
    echo $(( $2 / 512 )) > "${SYS_BLOCK}/$1/size"
    echo "${3:-0}" > "${SYS_BLOCK}/$1/removable"
    echo "${4:-Disk $1}" > "${SYS_BLOCK}/$1/device/model"
}

# fake_usb_disk <name> <bytes>: a disk behind USB (an SSD in an enclosure
# reports removable=0), linked from /sys/block as the kernel does
fake_usb_disk() {
    local real="${BATS_TEST_TMPDIR}/sys/devices/pci0000:00/0000:00:14.0/usb2/2-1/host0/block/$1"
    mkdir -p "${real}/device"
    echo $(( $2 / 512 )) > "${real}/size"
    echo 0 > "${real}/removable"
    echo "USB SSD" > "${real}/device/model"
    ln -s "${real}" "${SYS_BLOCK}/$1"
}

GIB=$(( 1024 * 1024 * 1024 ))
SHA_A=$(printf 'a%.0s' {1..64})
SHA_B=$(printf 'b%.0s' {1..64})
SHA_0=$(printf '0%.0s' {1..64})

# ---- Image layout ----

@test "installer_partition_table: GPT with one EFI partition, so the setup file lands on partition 1" {
    run installer_partition_table 128
    [ "$status" -eq 0 ]
    output_has "label: gpt"
    output_has "start=${PC_EFI_START}, size=262144, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
    [ "$(grep -c '^start=' <<< "$output")" -eq 1 ]
}

@test "installer_grub_cfg: boots the installer kernel and initrd from the key's FAT partition" {
    run installer_grub_cfg KURA-INST Kura
    [ "$status" -eq 0 ]
    output_has "search --no-floppy --label --set=root KURA-INST"
    output_has 'menuentry "Install Kura"'
    output_has "linux /kura/vmlinuz quiet console=ttyS0,115200 console=tty0"
    output_has "initrd /kura/initrd.img"
}

@test "installer_grub_cfg: extra kernel arguments (the boot test's kura.manifest=)" {
    run installer_grub_cfg KURA-INST Kura "kura.manifest=http://10.0.2.2:8088/manifest.json"
    output_has "linux /kura/vmlinuz quiet console=ttyS0,115200 console=tty0 kura.manifest=http://10.0.2.2:8088/manifest.json"
}

@test "installer_files: the signed shim and GRUB of the PC image, then the kernel and initrd" {
    run installer_files
    [ "$status" -eq 0 ]
    output_has "usr/lib/shim/shimx64.efi.signed EFI/BOOT/BOOTX64.EFI"
    output_has "usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed EFI/BOOT/grubx64.efi"
    output_has "vmlinuz kura/vmlinuz"
}

# ---- Release manifest ----

write_manifest() {
    cat > "${BATS_TEST_TMPDIR}/manifest.json" <<EOF
{"version":"v0.4.0","bundles":{"x86_64":{"url":"$1","sha256":"$2","size":10,
"extract_size":$3,"extract_sha256":"$4"}}}
EOF
}

@test "manifest_bundle: the PC image's URL, download sha256, size and image sha256" {
    write_manifest https://example.com/kura.img.zst "${SHA_A}" 4096 "${SHA_B}"
    run manifest_bundle "${BATS_TEST_TMPDIR}/manifest.json"
    [ "$status" -eq 0 ]
    [ "$output" = "https://example.com/kura.img.zst ${SHA_A} 4096 ${SHA_B}" ]
}

@test "manifest_bundle: refuses a manifest without checksums or with a bad size" {
    write_manifest https://example.com/kura.img.zst short 4096 "${SHA_B}"
    run manifest_bundle "${BATS_TEST_TMPDIR}/manifest.json"
    [ "$status" -ne 0 ]
    write_manifest https://example.com/kura.img.zst "${SHA_A}" big "${SHA_B}"
    run manifest_bundle "${BATS_TEST_TMPDIR}/manifest.json"
    [ "$status" -ne 0 ]
    echo "not json" > "${BATS_TEST_TMPDIR}/manifest.json"
    run manifest_bundle "${BATS_TEST_TMPDIR}/manifest.json"
    [ "$status" -ne 0 ]
}

@test "manifest_url: the latest release by default, kura.manifest= on the kernel command line overrides it" {
    echo "quiet console=tty0" > "${BATS_TEST_TMPDIR}/cmdline"
    run manifest_url "${BATS_TEST_TMPDIR}/cmdline"
    [ "$output" = "https://github.com/cbabil/kura/releases/latest/download/manifest.json" ]
    echo "quiet kura.manifest=http://10.0.2.2:8080/manifest.json console=tty0" > "${BATS_TEST_TMPDIR}/cmdline"
    run manifest_url "${BATS_TEST_TMPDIR}/cmdline"
    [ "$output" = "http://10.0.2.2:8080/manifest.json" ]
}

# ---- Target disk ----

@test "disk_candidates: internal disks big enough, never the key, removable media or virtual devices" {
    fake_disk nvme0n1 $(( 256 * GIB )) 0 "Samsung SSD"
    fake_disk sda $(( 32 * GIB )) 0 "USB key"
    fake_disk sdb $(( 64 * GIB )) 1 "Card reader"
    fake_disk mmcblk0 $(( 2 * GIB )) 0 "Small eMMC"
    fake_disk mmcblk0boot0 $(( 4 * 1024 * 1024 )) 0
    fake_disk loop0 $(( 8 * GIB )) 0
    fake_disk zram0 $(( 8 * GIB )) 0
    fake_disk sr0 $(( 8 * GIB )) 1
    run disk_candidates sda $(( 3 * GIB ))
    [ "$status" -eq 0 ]
    [ "$output" = "nvme0n1 $(( 256 * GIB )) Samsung SSD" ]
}

@test "disk_candidates: never a drive behind USB, even one that says it is not removable" {
    fake_disk nvme0n1 $(( 256 * GIB )) 0 "Samsung SSD"
    fake_usb_disk sdb $(( 500 * GIB ))
    run disk_candidates sda $(( 3 * GIB ))
    [ "$status" -eq 0 ]
    [ "$output" = "nvme0n1 $(( 256 * GIB )) Samsung SSD" ]
}

@test "disk_candidates: never an SD card in a built-in reader, eMMC is fine" {
    fake_disk mmcblk0 $(( 64 * GIB )) 0 "SD card"
    echo SD > "${SYS_BLOCK}/mmcblk0/device/type"
    fake_disk mmcblk1 $(( 64 * GIB )) 0 "eMMC"
    echo MMC > "${SYS_BLOCK}/mmcblk1/device/type"
    run disk_candidates sda $(( 3 * GIB ))
    [ "$status" -eq 0 ]
    [ "$output" = "mmcblk1 $(( 64 * GIB )) eMMC" ]
}

@test "pick_target: the one candidate" {
    fake_disk nvme0n1 $(( 256 * GIB )) 0 "Samsung SSD"
    run pick_target sda $(( 3 * GIB ))
    [ "$status" -eq 0 ]
    [ "$output" = "nvme0n1 $(( 256 * GIB )) Samsung SSD" ]
}

@test "pick_target: no disk, or two, stops and says why (nothing is written)" {
    run pick_target sda $(( 3 * GIB ))
    [ "$status" -ne 0 ]
    output_has "No internal drive"
    fake_disk nvme0n1 $(( 256 * GIB )) 0 "Samsung SSD"
    fake_disk sda1x $(( 500 * GIB )) 0 "SATA SSD"
    run pick_target sda $(( 3 * GIB ))
    [ "$status" -ne 0 ]
    output_has "More than one"
    output_has "nvme0n1"
    output_has "sda1x"
}

# ---- Countdown ----

@test "countdown: runs out without a key press, a key press cancels" {
    run countdown 1 < /dev/null
    [ "$status" -eq 0 ]
    run countdown 3 <<< "x"
    [ "$status" -ne 0 ]
}

# ---- Writing ----

# make_image <bytes>: an image and its .zst in BATS_TEST_TMPDIR
make_image() {
    head -c "$1" /dev/urandom > "${BATS_TEST_TMPDIR}/image.img"
    zstd -q -f "${BATS_TEST_TMPDIR}/image.img" -o "${BATS_TEST_TMPDIR}/image.img.zst"
}

stub_curl_stream() { stub_curl_copy "${BATS_TEST_TMPDIR}/image.img.zst"; }

@test "stream_image: downloads, checks the download and writes the image" {
    make_image 65536
    stub_curl_stream
    : > "${BATS_TEST_TMPDIR}/target"
    run stream_image https://example.com/kura.img.zst "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img.zst")" "${BATS_TEST_TMPDIR}/target"
    [ "$status" -eq 0 ]
    cmp "${BATS_TEST_TMPDIR}/image.img" "${BATS_TEST_TMPDIR}/target"
    file_has "${BATS_TEST_TMPDIR}/curl-url" "https://example.com/kura.img.zst"
}

@test "stream_image: a download that does not match its checksum fails" {
    make_image 65536
    stub_curl_stream
    : > "${BATS_TEST_TMPDIR}/target"
    run stream_image https://example.com/kura.img.zst "${SHA_0}" "${BATS_TEST_TMPDIR}/target"
    [ "$status" -ne 0 ]
    output_has "checksum"
}

@test "verify_written: reads back the image's bytes from the disk" {
    make_image 65536
    cat "${BATS_TEST_TMPDIR}/image.img" /dev/zero 2>/dev/null | head -c 131072 > "${BATS_TEST_TMPDIR}/disk"
    run verify_written "${BATS_TEST_TMPDIR}/disk" 65536 "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img")"
    [ "$status" -eq 0 ]
    printf 'X' | dd of="${BATS_TEST_TMPDIR}/disk" bs=1 seek=100 conv=notrunc 2>/dev/null
    run verify_written "${BATS_TEST_TMPDIR}/disk" 65536 "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img")"
    [ "$status" -ne 0 ]
}

# ---- Setup handoff and the key ----

@test "hand_over_setup: copies kura-setup.json to the installed system's EFI partition" {
    echo '{"version":1}' > "${KEY_DIR}/kura-setup.json"
    mkdir -p "${BATS_TEST_TMPDIR}/efi"
    run hand_over_setup "${BATS_TEST_TMPDIR}/efi"
    [ "$status" -eq 0 ]
    cmp "${KEY_DIR}/kura-setup.json" "${BATS_TEST_TMPDIR}/efi/kura-setup.json"
}

@test "hand_over_setup: nothing to copy without a setup file" {
    mkdir -p "${BATS_TEST_TMPDIR}/efi"
    run hand_over_setup "${BATS_TEST_TMPDIR}/efi"
    [ "$status" -eq 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/efi/kura-setup.json" ]
}

@test "mark_installed: removes the setup file (password hash, Wi-Fi key) and marks the key" {
    echo '{"version":1}' > "${KEY_DIR}/kura-setup.json"
    run mark_installed
    [ "$status" -eq 0 ]
    [ ! -e "${KEY_DIR}/kura-setup.json" ]
    [ -e "${KEY_DIR}/.installed" ]
    run already_installed
    [ "$status" -eq 0 ]
}

# ---- The whole run ----

# stub_install_tools: network, block devices and mounts faked; the target
# disk is a file under DEV_DIR
stub_install_tools() {
    fake_disk nvme0n1 $(( 256 * GIB )) 0 "Samsung SSD"
    : > "${DEV_DIR}/nvme0n1"
    net_up() { log_call net_up; }
    blockdev() { log_call blockdev "$@"; }
    sfdisk() { log_call sfdisk "$@"; }
    sync() { :; }
    with_mount() { log_call with_mount "$1"; mkdir -p "${BATS_TEST_TMPDIR}/newefi"; "$2" "${BATS_TEST_TMPDIR}/newefi"; }
    stub_curl_stream
    fetch_manifest() { cp "${BATS_TEST_TMPDIR}/manifest.json" "$2"; }
}

@test "install_kura: writes the internal disk, hands over the setup and marks the key" {
    make_image 65536
    write_manifest https://example.com/kura.img.zst "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img.zst")" 65536 "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img")"
    echo '{"version":1}' > "${KEY_DIR}/kura-setup.json"
    stub_install_tools
    run install_kura sda 0 < /dev/null
    [ "$status" -eq 0 ]
    cmp "${BATS_TEST_TMPDIR}/image.img" "${DEV_DIR}/nvme0n1"
    # read back from the drive, not the page cache
    file_has "${CALLS}" "blockdev --flushbufs ${DEV_DIR}/nvme0n1"
    file_has "${CALLS}" "sfdisk --relocate gpt-bak-std ${DEV_DIR}/nvme0n1"
    file_has "${CALLS}" "with_mount ${DEV_DIR}/nvme0n1p1"
    [ -e "${BATS_TEST_TMPDIR}/newefi/kura-setup.json" ]
    [ -e "${KEY_DIR}/.installed" ]
    [ ! -e "${KEY_DIR}/kura-setup.json" ]
}

@test "install_kura: a bad download changes nothing else (setup kept, key not marked)" {
    make_image 65536
    write_manifest https://example.com/kura.img.zst "${SHA_0}" 65536 "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img")"
    echo '{"version":1}' > "${KEY_DIR}/kura-setup.json"
    stub_install_tools
    run install_kura sda 0 < /dev/null
    [ "$status" -ne 0 ]
    [ -e "${KEY_DIR}/kura-setup.json" ]
    [ ! -e "${KEY_DIR}/.installed" ]
    ! grep -q with_mount "${CALLS}"
}

@test "install_kura: a key press during the countdown cancels before writing" {
    make_image 65536
    write_manifest https://example.com/kura.img.zst "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img.zst")" 65536 "$(file_sha256 "${BATS_TEST_TMPDIR}/image.img")"
    stub_install_tools
    run install_kura sda 3 <<< "x"
    [ "$status" -ne 0 ]
    output_has "Cancelled"
    [ ! -e "${BATS_TEST_TMPDIR}/curl-url" ]
    [ ! -s "${DEV_DIR}/nvme0n1" ]
}

@test "install_kura: a key that already installed Kura does nothing" {
    touch "${KEY_DIR}/.installed"
    stub_install_tools
    run install_kura sda 0 < /dev/null
    [ "$status" -eq 0 ]
    output_has "remove the USB key"
    [ ! -e "${CALLS}" ]
}

# ---- Initrd contents ----

@test "ldd_paths: the libraries and loader a binary needs, no vdso" {
    run ldd_paths <<'LDD'
	linux-vdso.so.1 (0x00007ffd3c5e2000)
	libcurl.so.4 => /lib/x86_64-linux-gnu/libcurl.so.4 (0x00007f2c1a000000)
	libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f2c19e00000)
	/lib64/ld-linux-x86-64.so.2 (0x00007f2c1a2b0000)
LDD
    [ "$status" -eq 0 ]
    [ "$output" = "/lib/x86_64-linux-gnu/libcurl.so.4
/lib/x86_64-linux-gnu/libc.so.6
/lib64/ld-linux-x86-64.so.2" ]
}

@test "module_paths: module files from modprobe --show-depends, built-ins skipped" {
    run module_paths <<'DEPS'
insmod /lib/modules/6.12.0-1-amd64/kernel/drivers/net/mii.ko.xz 
insmod /lib/modules/6.12.0-1-amd64/kernel/drivers/net/ethernet/realtek/r8169.ko.xz 
builtin crc32
DEPS
    [ "$status" -eq 0 ]
    [ "$output" = "/lib/modules/6.12.0-1-amd64/kernel/drivers/net/mii.ko.xz
/lib/modules/6.12.0-1-amd64/kernel/drivers/net/ethernet/realtek/r8169.ko.xz" ]
}

@test "installer modules: disks, USB keyboards (to cancel), wired network and FAT, for the NUC and QEMU" {
    for module in nvme vmd ahci usb_storage uas xhci_pci usbhid hid_generic e1000e igc r8169 \
            virtio_blk virtio_net vfat; do
        grep -qx "${module}" "${REPO_ROOT}/scripts/pc-installer/modules.list"
    done
}
