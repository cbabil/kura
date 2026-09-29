#!/usr/bin/env bats
# tests/shell/firstboot.bats — tests for scripts/common/firstboot.sh (runs on
# the device at first boot) and scripts/common/install-firstboot.sh (installs
# it into the image at build time). Device commands are stubbed.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

# Plain-command assertions: bash 3.2 (macOS) ignores a failing [[ ]] that is
# not the last command in a test, so pattern checks go through functions.
output_has() { [[ "$output" == *"$1"* ]]; }
file_has() { grep -qF -- "$2" "$1"; }

setup() {
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/firstboot.sh"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/install-firstboot.sh"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}"
    export CALLS
}

log_call() { echo "$*" >> "${CALLS}"; }

# ---- resize_root ----

stub_disk_tools() {  # stub_disk_tools <root-device> <parent-disk>
    ROOT_DEV="$1"; PARENT="$2"
    findmnt() { echo "${ROOT_DEV}"; }
    lsblk() { echo "${PARENT}"; }
    growpart() { log_call "growpart $*"; }
    resize2fs() { log_call "resize2fs $*"; }
}

@test "resize_root: grows the Pi SD card root partition" {
    stub_disk_tools /dev/mmcblk0p2 mmcblk0
    run resize_root
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "${CALLS}")" = "growpart /dev/mmcblk0 2" ]
    [ "$(sed -n 2p "${CALLS}")" = "resize2fs /dev/mmcblk0p2" ]
}

@test "resize_root: grows an x86 disk root partition" {
    stub_disk_tools /dev/sda1 sda
    run resize_root
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "${CALLS}")" = "growpart /dev/sda 1" ]
}

@test "resize_root: skips a live system whose root is not a partition" {
    stub_disk_tools overlay ""
    run resize_root
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

# ---- load_images ----

@test "load_images: loads every saved image" {
    mkdir -p "${BATS_TEST_TMPDIR}/images"
    touch "${BATS_TEST_TMPDIR}/images/traefik.tar" "${BATS_TEST_TMPDIR}/images/other.tar"
    docker() { log_call "docker $*"; }
    run load_images "${BATS_TEST_TMPDIR}/images"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "docker load -q -i ${BATS_TEST_TMPDIR}/images/traefik.tar"
    file_has "${CALLS}" "docker load -q -i ${BATS_TEST_TMPDIR}/images/other.tar"
}

@test "load_images: nothing to do when there are no saved images" {
    docker() { log_call "docker $*"; }
    run load_images "${BATS_TEST_TMPDIR}/missing"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

@test "load_images: fails when an image cannot be loaded" {
    mkdir -p "${BATS_TEST_TMPDIR}/images"
    touch "${BATS_TEST_TMPDIR}/images/traefik.tar"
    # shellcheck disable=SC2329  # invoked by load_images
    docker() { return 1; }
    run load_images "${BATS_TEST_TMPDIR}/images"
    [ "$status" -ne 0 ]
    output_has "traefik.tar"
}

# ---- ensure_network ----

@test "ensure_network: creates the network when it is missing" {
    docker() {
        log_call "docker $*"
        [ "$2" = "inspect" ] && return 1
        return 0
    }
    run ensure_network tomo_main tomo0
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "docker network create -o com.docker.network.bridge.name=tomo0 tomo_main"
}

@test "ensure_network: leaves an existing network alone" {
    docker() { log_call "docker $*"; }
    run ensure_network tomo_main tomo0
    [ "$status" -eq 0 ]
    run grep -q "network create" "${CALLS}"
    [ "$status" -ne 0 ]
}

# ---- run_firstboot ----

stub_all_ok() {
    resize_root() { log_call resize_root; }
    load_images() { log_call "load_images $1"; }
    ensure_network() { log_call "ensure_network $1 $2"; }
    apply_cloud_hostname() { log_call apply_cloud_hostname; }
}

@test "run_firstboot: runs every step and marks first boot done" {
    stub_all_ok
    run run_firstboot "${BATS_TEST_TMPDIR}/done" "${BATS_TEST_TMPDIR}/images"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "resize_root"
    file_has "${CALLS}" "load_images ${BATS_TEST_TMPDIR}/images"
    file_has "${CALLS}" "ensure_network tomo_main tomo0"
    [ -f "${BATS_TEST_TMPDIR}/done" ]
}

@test "run_firstboot: does nothing once marked done" {
    stub_all_ok
    touch "${BATS_TEST_TMPDIR}/done"
    run run_firstboot "${BATS_TEST_TMPDIR}/done" "${BATS_TEST_TMPDIR}/images"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

@test "run_firstboot: a failed step leaves first boot unmarked so it retries" {
    stub_all_ok
    # shellcheck disable=SC2329  # invoked by run_firstboot
    load_images() { return 1; }
    run run_firstboot "${BATS_TEST_TMPDIR}/done" "${BATS_TEST_TMPDIR}/images"
    [ "$status" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/done" ]
    file_has "${CALLS}" "ensure_network tomo_main"   # later steps still run
}

# ---- install_firstboot (build time) ----

@test "install_firstboot: installs the script with brand placeholders replaced" {
    run install_firstboot "${ROOTFS}" kura "Kura" "${REPO_ROOT}/scripts/common/firstboot.sh"
    [ "$status" -eq 0 ]
    [ -x "${ROOTFS}/usr/lib/kura/firstboot.sh" ]
    run grep -c "__BRAND" "${ROOTFS}/usr/lib/kura/firstboot.sh"
    [ "$output" = "0" ]
    file_has "${ROOTFS}/usr/lib/kura/firstboot.sh" "/var/lib/kura/.firstboot-done"
    file_has "${ROOTFS}/usr/lib/kura/firstboot.sh" "/usr/share/kura/images"
}

@test "install_firstboot: first-boot unit waits for Docker and runs before Tomo and the supervisor" {
    run install_firstboot "${ROOTFS}" kura "Kura" "${REPO_ROOT}/scripts/common/firstboot.sh"
    local unit="${ROOTFS}/usr/lib/systemd/system/kura-firstboot.service"
    file_has "${unit}" "After=docker.service"
    file_has "${unit}" "Before=tomod.service kura-supervisor.service"
    file_has "${unit}" "ConditionPathExists=!/var/lib/kura/.firstboot-done"
    # A failed step is retried while the device runs, not only at the next boot
    file_has "${unit}" "Restart=on-failure"
    file_has "${unit}" "RestartSec=30"
    file_has "${unit}" "StartLimitIntervalSec=0"
    [ "$(readlink "${ROOTFS}/etc/systemd/system/multi-user.target.wants/kura-firstboot.service")" = \
      "/usr/lib/systemd/system/kura-firstboot.service" ]
}

@test "install_firstboot: SSH keys are generated by their own unit, before sshd, without Docker" {
    run install_firstboot "${ROOTFS}" kura "Kura" "${REPO_ROOT}/scripts/common/firstboot.sh"
    local unit="${ROOTFS}/usr/lib/systemd/system/kura-ssh-keygen.service"
    file_has "${unit}" "Before=ssh.service ssh.socket"
    file_has "${unit}" "ExecStart=/usr/bin/ssh-keygen -A"
    run grep -q "docker" "${unit}"
    [ "$status" -ne 0 ]
    [ -L "${ROOTFS}/etc/systemd/system/multi-user.target.wants/kura-ssh-keygen.service" ]
}

# ---- reset_device_identity (build time) ----

@test "reset_device_identity: removes SSH host keys and empties machine-id" {
    mkdir -p "${ROOTFS}/etc/ssh" "${ROOTFS}/var/lib/dbus"
    touch "${ROOTFS}/etc/ssh/ssh_host_ed25519_key" "${ROOTFS}/etc/ssh/ssh_host_ed25519_key.pub" \
          "${ROOTFS}/etc/ssh/sshd_config"
    echo "0123456789abcdef0123456789abcdef" > "${ROOTFS}/etc/machine-id"
    echo "0123456789abcdef0123456789abcdef" > "${ROOTFS}/var/lib/dbus/machine-id"
    run reset_device_identity "${ROOTFS}"
    [ "$status" -eq 0 ]
    [ ! -e "${ROOTFS}/etc/ssh/ssh_host_ed25519_key" ]
    [ ! -e "${ROOTFS}/etc/ssh/ssh_host_ed25519_key.pub" ]
    [ -e "${ROOTFS}/etc/ssh/sshd_config" ]
    [ -f "${ROOTFS}/etc/machine-id" ]
    [ ! -s "${ROOTFS}/etc/machine-id" ]
    [ ! -e "${ROOTFS}/var/lib/dbus/machine-id" ]
}

@test "reset_device_identity: masks systemd-firstboot so an empty machine-id cannot prompt on the console" {
    run reset_device_identity "${ROOTFS}"
    [ "$status" -eq 0 ]
    [ "$(readlink "${ROOTFS}/etc/systemd/system/systemd-firstboot.service")" = "/dev/null" ]
}
