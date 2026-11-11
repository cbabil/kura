#!/usr/bin/env bats
# tests/shell/firstboot-storage.bats — the disk layout an imager asks for in
# kura-setup.json's "storage" key, built on first boot before the disks are
# mounted (scripts/common/firstboot-storage.sh, validated by
# firstboot-storage-check.sh). Disk commands are stubbed.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
GIB=1073741824
MIB=1048576

setup() {
    load test_helper
    SETUP_BRAND=kura
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/firstboot-storage.sh"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/install-firstboot.sh"
    SETUP_ROOT="${BATS_TEST_TMPDIR}/root"
    BOOT="${BATS_TEST_TMPDIR}/boot"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    mkdir -p "${SETUP_ROOT}/etc" "${BOOT}"
    F="${BOOT}/kura-setup.json"
    export CALLS
}

# storage <json>: a setup file with this storage key
storage() { printf '{"version":1,"storage":%s}\n' "$1" > "${F}"; }

SERVER='{"rootGiB":16,"tmpGiB":1,"volumes":[{"mount":"/var/log","sizeGiB":4},
  {"mount":"/var/tmp","sizeGiB":2},{"mount":"/home","sizeGiB":8},{"mount":"/var/lib/docker"}]}'

# ---- validate_storage ----

@test "validate_storage: accepts the server layout" {
    storage "${SERVER}"
    [ -z "$(validate_storage "${F}")" ]
}

@test "validate_storage: accepts a file without storage, and /tmp alone" {
    echo '{"version":1}' > "${F}"
    [ -z "$(validate_storage "${F}")" ]
    storage '{"tmpGiB":2}'
    [ -z "$(validate_storage "${F}")" ]
}

@test "validate_storage: names the first problem" {
    storage '[]'
    [ "$(validate_storage "${F}")" = "storage is not an object" ]
    storage '{"rootGiB":"16"}'
    [ "$(validate_storage "${F}")" = "the root size is not a whole number of GiB" ]
    storage '{"rootGiB":3}'
    [ "$(validate_storage "${F}")" = "the root needs at least 4 GiB" ]
    storage '{"rootGiB":16.5}'
    [ "$(validate_storage "${F}")" = "the root size is not a whole number of GiB" ]
    storage '{"tmpGiB":0}'
    [ "$(validate_storage "${F}")" = "the /tmp size is not a whole number of GiB" ]
    storage '{"volumes":[{"mount":"/home","sizeGiB":8}]}'
    [ "$(validate_storage "${F}")" = "volumes need a root size" ]
    storage '{"rootGiB":16,"volumes":{}}'
    [ "$(validate_storage "${F}")" = "volumes is not a list" ]
}

@test "validate_storage: only the listed mount points, each once, one taking the rest" {
    storage '{"rootGiB":16,"volumes":[{"mount":"/var","sizeGiB":8}]}'
    [ "$(validate_storage "${F}")" = "/var cannot be a separate volume" ]
    storage '{"rootGiB":16,"volumes":[{"mount":"/etc/../home","sizeGiB":8}]}'
    [ "$(validate_storage "${F}")" = "a volume's mount point is not allowed" ]
    storage '{"rootGiB":16,"volumes":[{"mount":"/home","sizeGiB":8},{"mount":"/home","sizeGiB":2}]}'
    [ "$(validate_storage "${F}")" = "/home is listed twice" ]
    storage '{"rootGiB":16,"volumes":[{"mount":"/home"},{"mount":"/srv"}]}'
    [ "$(validate_storage "${F}")" = "only one volume can take the rest of the disk" ]
    storage '{"rootGiB":16,"volumes":[{"mount":"/srv","sizeGiB":0}]}'
    [ "$(validate_storage "${F}")" = "the /srv size is not a whole number of GiB" ]
    storage '{"rootGiB":16,"volumes":["/srv"]}'
    [ "$(validate_storage "${F}")" = "a volume is not an object" ]
}

# ---- storage_plan ----

@test "storage_plan: lays out a 500 GB NVMe disk: root, then the volumes, the rest last" {
    storage "${SERVER}"
    run storage_plan "${F}" 500107862016 $(( 257 * MIB )) $(( 3 * GIB ))
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "root $(( 16 * GIB ))" ]
    [ "${lines[1]}" = "pv $(( 257 * MIB + 16 * GIB ))" ]
    [ "${lines[2]}" = "lv var-log /var/log 4 noexec,nosuid,nodev" ]
    [ "${lines[3]}" = "lv var-tmp /var/tmp 2 noexec,nosuid,nodev" ]
    [ "${lines[4]}" = "lv home /home 8 nosuid,nodev" ]
    [ "${lines[5]}" = "lv var-lib-docker /var/lib/docker rest defaults" ]
}

@test "storage_plan: a 64 GB card fits the server layout" {
    storage "${SERVER}"
    run storage_plan "${F}" 63864569856 $(( 260 * MIB )) $(( 2 * GIB ))
    [ "${lines[0]}" = "root $(( 16 * GIB ))" ]
}

@test "storage_plan: a 32 GB card does not, and says by how much" {
    storage "${SERVER}"
    run storage_plan "${F}" 31914983424 $(( 260 * MIB )) $(( 2 * GIB ))
    [ "$status" -eq 0 ]
    [ "$output" = "skipped: needs 34 GB, disk has 31 GB" ]
}

@test "storage_plan: never shrinks the root, and keeps sizes in whole MiB" {
    storage '{"rootGiB":4,"volumes":[{"mount":"/srv","sizeGiB":1}]}'
    run storage_plan "${F}" $(( 64 * GIB )) $(( 260 * MIB )) $(( 5 * GIB + 512 ))
    [ "${lines[0]}" = "root $(( 5 * GIB + MIB ))" ]
    [ "${lines[1]}" = "pv $(( 260 * MIB + 5 * GIB + MIB ))" ]
}

@test "validate_storage: a root size needs at least one volume" {
    storage '{"rootGiB":16}'
    [ "$(validate_storage "${F}")" = "a root size needs at least one volume" ]
    storage '{"rootGiB":16,"volumes":[]}'
    [ "$(validate_storage "${F}")" = "a root size needs at least one volume" ]
}

@test "storage_plan: nothing to lay out without a root size" {
    storage '{"tmpGiB":1}'
    run storage_plan "${F}" $(( 64 * GIB )) $(( 260 * MIB )) $(( 2 * GIB ))
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ---- apply_storage_dir ----

stub_storage_device() {  # an NVMe disk of <bytes>, root on p2 at 257 MiB, 3 GiB
    stub_disk_tools /dev/nvme0n1p2 nvme0n1
    DISK_BYTES="$1"
    STORAGE_SYS="${BATS_TEST_TMPDIR}/sys"
    mkdir -p "${STORAGE_SYS}/nvme0n1p2"
    echo $(( 257 * 2048 )) > "${STORAGE_SYS}/nvme0n1p2/start"
    echo $(( 3 * 2 * 1024 * 1024 )) > "${STORAGE_SYS}/nvme0n1p2/size"
    blockdev() { echo "${DISK_BYTES}"; }
    blkid() { echo gpt; }
    sfdisk() { log_call "sfdisk $* <<< $(cat)"; }
    partx() { log_call "partx $*"; }
    resize2fs() { log_call "resize2fs $*"; }
    pvcreate() { log_call "pvcreate $*"; }
    vgcreate() { log_call "vgcreate $*"; }
    lvcreate() { log_call "lvcreate $*"; }
    udevadm() { :; }
    mkfs.ext4() { log_call "mkfs.ext4 $*"; }
    mount() { log_call "mount $*"; }
    umount() { log_call "umount $*"; }
    cp() { log_call "cp $*"; }
}

@test "apply_storage_dir: no setup file, or no storage key: nothing happens" {
    stub_storage_device 500107862016
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    echo '{"version":1,"hostname":"a"}' > "${F}"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
    [ ! -e "${SETUP_ROOT}/var/lib/kura/storage-status" ]
}

@test "apply_storage_dir: sizes the root, then builds and mounts the volumes" {
    stub_storage_device 500107862016
    storage "${SERVER}"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "sfdisk --relocate gpt-bak-std /dev/nvme0n1"
    file_has "${CALLS}" "sfdisk --no-reread -N 2 /dev/nvme0n1 <<< ,16384MiB"
    file_has "${CALLS}" "sfdisk --no-reread --append /dev/nvme0n1 <<< $(( 257 + 16 * 1024 ))MiB,,lvm"
    file_has "${CALLS}" "partx -u --nr 2 /dev/nvme0n1"
    file_has "${CALLS}" "partx -a --nr 3 /dev/nvme0n1"
    file_has "${CALLS}" "resize2fs /dev/nvme0n1p2"
    file_has "${CALLS}" "pvcreate -ff -y /dev/nvme0n1p3"
    file_has "${CALLS}" "vgcreate kura /dev/nvme0n1p3"
    file_has "${CALLS}" "lvcreate -y -n var-log -L 4G kura"
    file_has "${CALLS}" "lvcreate -y -n var-lib-docker -l 100%FREE kura"
    file_has "${CALLS}" "mkfs.ext4 -q -L var-lib-docker /dev/kura/var-lib-docker"
    file_has "${CALLS}" "mount -o noexec,nosuid,nodev /dev/kura/var-log ${SETUP_ROOT}/var/log"
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/var-log /var/log ext4 noexec,nosuid,nodev 0 2"
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/home /home ext4 nosuid,nodev 0 2"
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/var-lib-docker /var/lib/docker ext4 defaults 0 2"
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "applied" ]
}

@test "apply_storage_dir: moves what a folder holds onto its volume" {
    stub_storage_device 500107862016
    storage '{"rootGiB":16,"volumes":[{"mount":"/var/log"}]}'
    mkdir -p "${SETUP_ROOT}/var/log/apt"
    touch "${SETUP_ROOT}/var/log/apt/history.log"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "cp -a ${SETUP_ROOT}/var/log/."
    [ -d "${SETUP_ROOT}/var/log" ]
    [ ! -e "${SETUP_ROOT}/var/log/apt" ]
    # the copy comes before the folder is emptied and the volume mounted in it
    [ "$(grep -n '^cp -a' "${CALLS}" | cut -d: -f1)" -lt \
      "$(grep -n "^mount -o .* ${SETUP_ROOT}/var/log$" "${CALLS}" | cut -d: -f1)" ]
}

@test "apply_storage_dir: a layout that does not fit is skipped, the disk untouched" {
    stub_storage_device 31914983424
    storage "${SERVER}"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "skipped: needs 34 GB, disk has 31 GB" ]
}

@test "apply_storage_dir: an invalid storage key is skipped, the disk untouched" {
    stub_storage_device 500107862016
    storage '{"rootGiB":16,"volumes":[{"mount":"/var"}]}'
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "skipped: /var cannot be a separate volume" ]
}

@test "apply_storage_dir: an MBR disk (the Pi's) has no backup table to move" {
    stub_storage_device 500107862016
    blkid() { echo dos; }
    storage "${SERVER}"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    run grep -c "relocate" "${CALLS}"
    [ "$output" = "0" ]
}

@test "apply_storage_dir: each volume is in fstab before its folder is emptied" {
    stub_storage_device 500107862016
    storage "${SERVER}"
    lvcreate() { log_call "lvcreate $*"; [[ "$*" != *home* ]]; }
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 1 ]
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/var-log /var/log"
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/var-tmp /var/tmp"
    run grep -c "/dev/kura/home" "${SETUP_ROOT}/etc/fstab"
    [ "$output" = "0" ]
    run grep -c "^# kura disk layout" "${SETUP_ROOT}/etc/fstab"
    [ "$output" = "1" ]
}

@test "run_storage: marks itself done before building, so a cut-off run is not repeated" {
    boot_partition() { return 1; }
    run_storage "${SETUP_ROOT}/var/lib/kura/.storage-done"
    [ -f "${SETUP_ROOT}/var/lib/kura/.storage-done" ]
    [ "$(grep -n 'touch "\$1"' "${REPO_ROOT}/scripts/common/firstboot-storage.sh" | cut -d: -f1)" -lt \
      "$(grep -n 'with_mount "\${dev}" copy_setup_file' "${REPO_ROOT}/scripts/common/firstboot-storage.sh" | cut -d: -f1)" ]
}

@test "apply_storage_dir: a failing step is recorded and fails the unit" {
    stub_storage_device 500107862016
    storage "${SERVER}"
    vgcreate() { return 5; }
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 1 ]
    matches "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" "failed: *"
}

@test "apply_storage_dir: a root that is not a disk partition is left alone" {
    stub_storage_device 500107862016
    stub_disk_tools overlay ""
    storage "${SERVER}"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

@test "storage_applied: true once the layout was built" {
    run storage_applied
    [ "$status" -ne 0 ]
    mkdir -p "${SETUP_ROOT}/var/lib/kura"
    echo "skipped: x" > "${SETUP_ROOT}/var/lib/kura/storage-status"
    run storage_applied
    [ "$status" -ne 0 ]
    echo "applied" > "${SETUP_ROOT}/var/lib/kura/storage-status"
    run storage_applied
    [ "$status" -eq 0 ]
}

# ---- the unit (build time) ----

@test "install_firstboot: the disk layout runs once, before anything mounts or writes to those folders" {
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}"
    run install_firstboot "${ROOTFS}" kura "Kura" "${REPO_ROOT}/scripts/common"
    [ "$status" -eq 0 ]
    local unit="${ROOTFS}/usr/lib/systemd/system/kura-storage.service"
    file_has "${unit}" "DefaultDependencies=no"
    file_has "${unit}" "After=systemd-remount-fs.service systemd-udevd.service"
    file_has "${unit}" "Before=local-fs.target boot-efi.mount tmp.mount systemd-journal-flush.service docker.service kura-security.service kura-firstboot.service"
    # scratch mounts never under /tmp, which tmp.mount may cover
    file_has "${unit}" "Environment=TMPDIR=/run"
    file_has "${unit}" "ConditionPathExists=!/var/lib/kura/.storage-done"
    file_has "${unit}" "ExecStart=/usr/lib/kura/firstboot-storage.sh"
    [ -x "${ROOTFS}/usr/lib/kura/firstboot-storage.sh" ]
    [ -x "${ROOTFS}/usr/lib/kura/firstboot-storage-check.sh" ]
    [ "$(readlink "${ROOTFS}/etc/systemd/system/local-fs.target.wants/kura-storage.service")" = \
      "/usr/lib/systemd/system/kura-storage.service" ]
}

@test "the image has the disk layout tools" {
    file_has "${REPO_ROOT}/config/packages-common.list" "lvm2"
    file_has "${REPO_ROOT}/config/packages-common.list" "fdisk"
}
