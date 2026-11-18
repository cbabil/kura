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

@test "validate_storage: each folder once, one taking the rest" {
    storage '{"rootGiB":16,"volumes":[{"mount":"/home","sizeGiB":8},{"mount":"/home","sizeGiB":2}]}'
    [ "$(validate_storage "${F}")" = "/home is listed twice" ]
    storage '{"rootGiB":16,"volumes":[{"mount":"/home"},{"mount":"/srv"}]}'
    [ "$(validate_storage "${F}")" = "only one volume can take the rest of the disk" ]
    storage '{"rootGiB":16,"volumes":[{"mount":"/srv","sizeGiB":0}]}'
    [ "$(validate_storage "${F}")" = "the /srv size is not a whole number of GiB" ]
    storage '{"rootGiB":16,"volumes":["/srv"]}'
    [ "$(validate_storage "${F}")" = "a volume is not an object" ]
}

@test "validate_storage: any plain folder, /var and /var/lib included" {
    for m in /var /var/lib /var/cache /tmp /echange /data/media /srv/my_app.d; do
        storage "{\"rootGiB\":16,\"volumes\":[{\"mount\":\"${m}\",\"sizeGiB\":4}]}"
        [ -z "$(validate_storage "${F}")" ] || { echo "${m} rejected"; return 1; }
    done
}

@test "validate_storage: a folder that is not a plain absolute path" {
    for m in "" "home" "/" "/home/" "//home" "/etc/../home" "/a/./b" "/a b" '/a;b' \
             "/$(printf 'x%.0s' {1..64})"; do
        storage "{\"rootGiB\":16,\"volumes\":[{\"mount\":\"${m}\",\"sizeGiB\":4}]}"
        [ "$(validate_storage "${F}")" = "a volume's folder is not a plain absolute path" ] ||
            { echo "${m} accepted"; return 1; }
    done
    storage '{"rootGiB":16,"volumes":[{"sizeGiB":4}]}'
    [ "$(validate_storage "${F}")" = "a volume's folder is not a plain absolute path" ]
}

@test "validate_storage: system folders, the brand's state and folders under /tmp stay on the root" {
    for m in /boot /boot/efi /etc /etc/ssh /usr /usr/local /bin /sbin /lib /lib64 /dev /proc /sys \
             /run /root /var/run /var/lock /var/lib/kura /var/lib/kura/x /tmp/x; do
        storage "{\"rootGiB\":16,\"volumes\":[{\"mount\":\"${m}\",\"sizeGiB\":4}]}"
        [ "$(validate_storage "${F}")" = "${m} cannot be a separate volume" ] ||
            { echo "${m}: $(validate_storage "${F}")"; return 1; }
    done
}

@test "validate_storage: names LVM refuses or keeps for itself" {
    for m in /-data /srv/-x /snapshot /pvmove /data_tmeta /a/b_rimage_1 /x_cdata; do
        storage "{\"rootGiB\":16,\"volumes\":[{\"mount\":\"${m}\",\"sizeGiB\":4}]}"
        [ "$(validate_storage "${F}")" = "${m} cannot be a separate volume" ] ||
            { echo "${m}: $(validate_storage "${F}")"; return 1; }
    done
    storage '{"rootGiB":16,"volumes":[{"mount":"/srv/snapshots","sizeGiB":4},{"mount":"/data-x","sizeGiB":4}]}'
    [ -z "$(validate_storage "${F}")" ]
}

@test "validate_storage: two folders that would share a volume name" {
    storage '{"rootGiB":16,"volumes":[{"mount":"/a/b","sizeGiB":4},{"mount":"/a-b","sizeGiB":4}]}'
    [ "$(validate_storage "${F}")" = "/a/b and /a-b would share a volume name" ]
    storage '{"rootGiB":16,"swapGiB":2,"volumes":[{"mount":"/swap","sizeGiB":4}]}'
    [ "$(validate_storage "${F}")" = "/swap would share the swap volume's name" ]
}

@test "validate_storage: swap" {
    storage '{"rootGiB":16,"swapGiB":8,"volumes":[{"mount":"/home"}]}'
    [ -z "$(validate_storage "${F}")" ]
    storage '{"rootGiB":16,"swapGiB":8}'
    [ -z "$(validate_storage "${F}")" ]
    storage '{"rootGiB":16,"swapGiB":0,"volumes":[{"mount":"/home"}]}'
    [ "$(validate_storage "${F}")" = "the swap size is not a whole number of GiB" ]
    storage '{"swapGiB":8}'
    [ "$(validate_storage "${F}")" = "swap needs a root size" ]
}

@test "validate_storage: /tmp is either in RAM or a volume" {
    storage '{"rootGiB":16,"tmpGiB":2,"volumes":[{"mount":"/tmp","sizeGiB":4}]}'
    [ "$(validate_storage "${F}")" = "/tmp is either in RAM or a volume" ]
}

# ---- storage_plan ----

@test "storage_plan: lays out a 500 GB NVMe disk: root, then the volumes, parents first" {
    storage "${SERVER}"
    run storage_plan "${F}" 500107862016 $(( 257 * MIB )) $(( 3 * GIB ))
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "root $(( 16 * GIB ))" ]
    [ "${lines[1]}" = "pv $(( 257 * MIB + 16 * GIB ))" ]
    [ "${lines[2]}" = "lv home /home 8 nosuid,nodev" ]
    [ "${lines[3]}" = "lv var-log /var/log 4 noexec,nosuid,nodev" ]
    [ "${lines[4]}" = "lv var-tmp /var/tmp 2 noexec,nosuid,nodev" ]
    [ "${lines[5]}" = "lv var-lib-docker /var/lib/docker rest defaults" ]
}

# the 256 GB layout the user asked for (their 1 TB machine, scaled down)
FULL='{"rootGiB":20,"swapGiB":8,"volumes":[
  {"mount":"/var/lib/docker","sizeGiB":40},{"mount":"/var/lib","sizeGiB":10},{"mount":"/var","sizeGiB":8},
  {"mount":"/var/log","sizeGiB":4},{"mount":"/var/cache","sizeGiB":8},{"mount":"/tmp","sizeGiB":4},
  {"mount":"/opt","sizeGiB":10},{"mount":"/home","sizeGiB":40},{"mount":"/srv","sizeGiB":50},
  {"mount":"/echange","sizeGiB":20}]}'

@test "storage_plan: the full layout fits a 256 GB SSD with room to grow, parents first" {
    storage "${FULL}"
    [ -z "$(validate_storage "${F}")" ]
    run storage_plan "${F}" 256060514304 $(( 257 * MIB )) $(( 3 * GIB ))
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "root $(( 20 * GIB ))" ]
    [ "${lines[2]}" = "swap 8" ]
    # depth order, JSON order within a depth
    [ "$(grep '^lv ' <<< "${output}" | cut -d' ' -f3 | tr '\n' ' ')" = \
      "/var /tmp /opt /home /srv /echange /var/lib /var/log /var/cache /var/lib/docker " ]
    output_has "lv var /var 8 defaults"
    output_has "lv var-lib /var/lib 10 defaults"
    output_has "lv var-cache /var/cache 8 defaults"
    output_has "lv var-log /var/log 4 noexec,nosuid,nodev"
    output_has "lv tmp /tmp 4 noexec,nosuid,nodev"
    output_has "lv echange /echange 20 nosuid,nodev"
    # about 16 GiB left in the volume group for lvextend
    run storage_plan "${F}" $(( 256060514304 - 16 * GIB )) $(( 257 * MIB )) $(( 3 * GIB ))
    [ "${lines[0]}" = "root $(( 20 * GIB ))" ]
}

@test "storage_plan: swap counts in the space needed" {
    storage '{"rootGiB":16,"swapGiB":40,"volumes":[{"mount":"/home","sizeGiB":8}]}'
    run storage_plan "${F}" $(( 64 * GIB )) $(( 260 * MIB )) $(( 2 * GIB ))
    [ "$output" = "skipped: needs 70 GB, disk has 68 GB" ]
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
    mkswap() { log_call "mkswap $*"; }
    systemctl() { log_call "systemctl $*"; }
    journalctl() { log_call "journalctl $*"; }
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

@test "apply_storage_dir: sizes the root, builds and fills the volumes, writes fstab, restarts" {
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
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/var-log /var/log ext4 noexec,nosuid,nodev 0 2"
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/home /home ext4 nosuid,nodev 0 2"
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/var-lib-docker /var/lib/docker ext4 defaults 0 2"
    # nothing is mounted over a folder in use: the restart mounts them all
    run grep -c "^mount -o [a-z,]* /dev/kura/" "${CALLS}"
    [ "$output" = "0" ]
    file_has "${CALLS}" "journalctl --flush"
    file_has "${CALLS}" "systemctl --no-block reboot"
    # the finishing pass on the next boot cleans up and says it was applied
    [ -f "${SETUP_ROOT}/var/lib/kura/.storage-pending" ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "restarting" ]
}

@test "apply_storage_dir: copies what a folder holds onto its volume and leaves the root as it was" {
    stub_storage_device 500107862016
    storage '{"rootGiB":16,"volumes":[{"mount":"/var/log"}]}'
    mkdir -p "${SETUP_ROOT}/var/log/apt"
    touch "${SETUP_ROOT}/var/log/apt/history.log"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "cp -ax ${SETUP_ROOT}/var/log/."
    [ -f "${SETUP_ROOT}/var/log/apt/history.log" ]
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
    storage '{"rootGiB":16,"volumes":[{"mount":"/etc"}]}'
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "skipped: /etc cannot be a separate volume" ]
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

@test "apply_storage_dir: a failure leaves fstab as it was and does not restart" {
    stub_storage_device 500107862016
    storage "${SERVER}"
    echo "/dev/sda2 / ext4 defaults 0 1" > "${SETUP_ROOT}/etc/fstab"
    mkfs.ext4() { log_call "mkfs.ext4 $*"; [[ "$*" != *var-tmp* ]]; }
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 1 ]
    [ "$(cat "${SETUP_ROOT}/etc/fstab")" = "/dev/sda2 / ext4 defaults 0 1" ]
    run grep -c "reboot" "${CALLS}"
    [ "$output" = "0" ]
    [ ! -e "${SETUP_ROOT}/var/lib/kura/.storage-pending" ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "failed: formatting /var/tmp" ]
}

@test "apply_storage_dir: every volume is created before any folder moves, the rest last" {
    stub_storage_device 500107862016
    storage "${SERVER}"
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ "$(grep '^lvcreate' "${CALLS}" | cut -d' ' -f4 | tr '\n' ' ')" = "home var-log var-tmp var-lib-docker " ]
    [ "$(grep -n '^lvcreate .*var-lib-docker' "${CALLS}" | cut -d: -f1)" -lt \
      "$(grep -n '^mkfs.ext4' "${CALLS}" | head -1 | cut -d: -f1)" ]
}

@test "apply_storage_dir: a folder's copy leaves out the folders with volumes of their own" {
    stub_storage_device 500107862016
    storage '{"rootGiB":16,"volumes":[{"mount":"/var/lib/docker"},{"mount":"/var/lib","sizeGiB":20},
      {"mount":"/var","sizeGiB":8}]}'
    mkdir -p "${SETUP_ROOT}/var/lib/docker/image" "${SETUP_ROOT}/var/lib/dpkg" "${SETUP_ROOT}/var/cache"
    touch "${SETUP_ROOT}/var/lib/docker/image/layer" "${SETUP_ROOT}/var/lib/dpkg/status"
    COPIES="${BATS_TEST_TMPDIR}/copies"
    # each volume's copy in a scratch folder of its own (_var, _var_lib, ...)
    copy_folder() {
        local into="${COPIES}/${MOVE_MOUNT//\//_}"
        mkdir -p "${into}" && command cp -R "${MOVE_FROM}/." "${into}/" && prune_nested "${into}" "${MOVE_MOUNT}"
    }
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    # each byte lands on one volume only; the mount points stay, empty
    [ -f "${COPIES}/_var_lib_docker/image/layer" ]
    [ -f "${COPIES}/_var_lib/dpkg/status" ]
    [ -d "${COPIES}/_var_lib/docker" ]
    [ -z "$(ls -A "${COPIES}/_var_lib/docker")" ]
    [ -d "${COPIES}/_var/cache" ]
    [ -d "${COPIES}/_var/lib" ]
    [ -z "$(ls -A "${COPIES}/_var/lib")" ]
}

@test "apply_storage_dir: swap gets its volume and an fstab line" {
    stub_storage_device 500107862016
    storage '{"rootGiB":16,"swapGiB":8,"volumes":[{"mount":"/home"}]}'
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "lvcreate -y -n swap -L 8G kura"
    file_has "${CALLS}" "mkswap -L swap /dev/kura/swap"
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/swap none swap sw 0 0"
    # created before the volume that takes the rest
    [ "$(grep -n '^lvcreate .* swap ' "${CALLS}" | cut -d: -f1)" -lt \
      "$(grep -n '^lvcreate .* home ' "${CALLS}" | cut -d: -f1)" ]
}

@test "apply_storage_dir: swap alone next to the root" {
    stub_storage_device 500107862016
    storage '{"rootGiB":16,"swapGiB":4}'
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/swap none swap sw 0 0"
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "restarting" ]
}

@test "apply_storage_dir: /tmp on disk, with long names labelled within ext4's 16 characters" {
    stub_storage_device 500107862016
    storage '{"rootGiB":16,"volumes":[{"mount":"/tmp","sizeGiB":4},{"mount":"/srv/photos-archive"}]}'
    run apply_storage_dir "${BOOT}"
    [ "$status" -eq 0 ]
    file_has "${SETUP_ROOT}/etc/fstab" "/dev/kura/tmp /tmp ext4 noexec,nosuid,nodev 0 2"
    file_has "${CALLS}" "mkfs.ext4 -q -L srv-photos-archi /dev/kura/srv-photos-archive"
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

# ---- finish_storage (the next boot, volumes mounted) ----

stub_root_view() {  # the bind mount of / shows SETUP_ROOT as it is underneath
    mount() { log_call "mount $*"; [ "$1" != --bind ] || { rmdir "$3"; ln -s "${SETUP_ROOT}" "$3"; }; }
    umount() { log_call "umount $*"; rm -f "$1"; mkdir "$1"; }
    mountpoint() { [[ " ${MOUNTED:-} " == *" ${2#"${SETUP_ROOT}"} "* ]]; }
    MOUNTED="/var/log /home /var /var/lib/docker"
    LIVE="${BATS_TEST_TMPDIR}/live"   # what the mounted /var/log shows
}

@test "finish_storage: clears what the volumes now cover from the root, and says it was applied" {
    stub_root_view
    mkdir -p "${SETUP_ROOT}/var/lib/kura" "${SETUP_ROOT}/var/log/apt" "${SETUP_ROOT}/home/u"
    touch "${SETUP_ROOT}/var/lib/kura/.storage-pending" "${SETUP_ROOT}/var/log/apt/h.log" "${SETUP_ROOT}/home/u/f"
    printf '%s\n' "/dev/sda2 / ext4 defaults 0 1" "# kura disk layout" \
        "/dev/kura/swap none swap sw 0 0" "/dev/kura/var-log /var/log ext4 noexec,nosuid,nodev 0 2" \
        "/dev/kura/home /home ext4 nosuid,nodev 0 2" > "${SETUP_ROOT}/etc/fstab"
    run finish_storage
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "mount --bind ${SETUP_ROOT} "
    [ -d "${SETUP_ROOT}/var/log" ]
    [ -d "${SETUP_ROOT}/home" ]
    [ -z "$(ls -A "${SETUP_ROOT}/var/log")" ]
    [ -z "$(ls -A "${SETUP_ROOT}/home")" ]
    [ -s "${SETUP_ROOT}/etc/fstab" ]
    [ ! -e "${SETUP_ROOT}/var/lib/kura/.storage-pending" ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "applied" ]
}

@test "finish_storage: a volume that did not mount keeps its folder, and says so" {
    stub_root_view
    MOUNTED="/var/log"
    mkdir -p "${SETUP_ROOT}/var/lib/kura" "${SETUP_ROOT}/var/log/apt" "${SETUP_ROOT}/home/u"
    touch "${SETUP_ROOT}/var/lib/kura/.storage-pending" "${SETUP_ROOT}/home/u/f"
    printf '%s\n' "# kura disk layout" "/dev/kura/var-log /var/log ext4 noexec,nosuid,nodev 0 2" \
        "/dev/kura/home /home ext4 nosuid,nodev 0 2" > "${SETUP_ROOT}/etc/fstab"
    run finish_storage
    [ "$status" -eq 1 ]
    [ -f "${SETUP_ROOT}/home/u/f" ]
    # first boot's setup still runs, and the login screen says what failed
    [ ! -e "${SETUP_ROOT}/var/lib/kura/.storage-pending" ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/storage-status")" = "failed: mounting /home" ]
}

@test "finish_storage: keeps the first boot's journal on the volume that now holds /var/log" {
    stub_root_view
    mkdir -p "${SETUP_ROOT}/var/log/journal/abc"
    touch "${SETUP_ROOT}/var/log/journal/abc/system.journal"
    printf '%s\n' "# kura disk layout" "/dev/kura/var-log /var/log ext4 noexec,nosuid,nodev 0 2" \
        > "${SETUP_ROOT}/etc/fstab"
    cp() { log_call "cp $*"; }
    run finish_storage
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "/var/log/journal/abc/system.journal ${SETUP_ROOT}/var/log/journal/abc/layout-first-boot.journal"
}

@test "finish_storage: the root's copy of a nested folder goes with its parent's" {
    stub_root_view
    mkdir -p "${SETUP_ROOT}/var/lib/docker/x"
    printf '%s\n' "# kura disk layout" "/dev/kura/var /var ext4 defaults 0 2" \
        "/dev/kura/var-lib-docker /var/lib/docker ext4 defaults 0 2" > "${SETUP_ROOT}/etc/fstab"
    run finish_storage
    [ "$status" -eq 0 ]
    [ ! -e "${SETUP_ROOT}/var/lib/docker" ]
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
    # its done flag may live on a volume: checked once that volume is mounted
    file_has "${unit}" "RequiresMountsFor=/var/lib/kura"
    # the folders move across a restart: no unit has to be listed to keep out
    run grep -c "systemd-random-seed" "${unit}"
    [ "$output" = "0" ]
    local finish="${ROOTFS}/usr/lib/systemd/system/kura-storage-finish.service"
    file_has "${finish}" "DefaultDependencies=no"
    file_has "${finish}" "After=local-fs.target"
    file_has "${finish}" "Before=sysinit.target docker.service kura-firstboot.service"
    file_has "${finish}" "ConditionPathExists=/var/lib/kura/.storage-pending"
    file_has "${finish}" "ExecStart=/usr/lib/kura/firstboot-storage.sh finish"
    [ "$(readlink "${ROOTFS}/etc/systemd/system/sysinit.target.wants/kura-storage-finish.service")" = \
      "/usr/lib/systemd/system/kura-storage-finish.service" ]
    # first boot's setup waits for the restart that puts the volumes in place
    file_has "${ROOTFS}/usr/lib/systemd/system/kura-firstboot.service" \
        "ConditionPathExists=!/var/lib/kura/.storage-pending"
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
