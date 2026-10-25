#!/usr/bin/env bats
# tests/shell/firstboot.bats — tests for scripts/common/firstboot.sh (runs on
# the device at first boot) and scripts/common/install-firstboot.sh (installs
# it into the image at build time). Device commands are stubbed.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/firstboot.sh"
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/install-firstboot.sh"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}"
    export CALLS
}

# ---- resize_root ----

stub_resize_tools() {  # stub_resize_tools <root-device> <parent-disk>
    stub_disk_tools "$1" "$2"
    growpart() { log_call "growpart $*"; }
    resize2fs() { log_call "resize2fs $*"; }
}

@test "resize_root: grows the Pi SD card root partition" {
    stub_resize_tools /dev/mmcblk0p2 mmcblk0
    run resize_root
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "${CALLS}")" = "growpart /dev/mmcblk0 2" ]
    [ "$(sed -n 2p "${CALLS}")" = "resize2fs /dev/mmcblk0p2" ]
}

@test "resize_root: grows an x86 disk root partition" {
    stub_resize_tools /dev/sda1 sda
    run resize_root
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "${CALLS}")" = "growpart /dev/sda 1" ]
}

@test "resize_root: skips a live system whose root is not a partition" {
    stub_resize_tools overlay ""
    run resize_root
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

# ---- apply_cloud_hostname ----

@test "cloud_hostname_from: hands a valid user-data hostname to os-config" {
    SETUP_ROOT="${BATS_TEST_TMPDIR}/root"
    mkdir -p "${SETUP_ROOT}/etc/kura" "${BATS_TEST_TMPDIR}/cd"
    cp "${REPO_ROOT}/overlay/common/etc/kura/config.json" "${SETUP_ROOT}/etc/kura/"
    printf '#cloud-config\nhostname: vm-01\n' > "${BATS_TEST_TMPDIR}/cd/user-data"
    SETUP_BRAND=kura run cloud_hostname_from "${BATS_TEST_TMPDIR}/cd"
    [ "$status" -eq 0 ]
    [ "$(jq -r .hostname "${SETUP_ROOT}/etc/kura/config.json")" = "vm-01" ]
}

@test "cloud_hostname_from: ignores an invalid hostname" {
    SETUP_ROOT="${BATS_TEST_TMPDIR}/root"
    mkdir -p "${SETUP_ROOT}/etc/kura" "${BATS_TEST_TMPDIR}/cd"
    cp "${REPO_ROOT}/overlay/common/etc/kura/config.json" "${SETUP_ROOT}/etc/kura/"
    printf 'hostname: $(reboot)\n' > "${BATS_TEST_TMPDIR}/cd/user-data"
    SETUP_BRAND=kura run cloud_hostname_from "${BATS_TEST_TMPDIR}/cd"
    [ "$status" -eq 0 ]
    [ "$(jq -r .hostname "${SETUP_ROOT}/etc/kura/config.json")" = "kura" ]
}

# ---- run_firstboot ----

stub_all_ok() {
    apply_setup() { log_call apply_setup; }
    resize_root() { log_call resize_root; }
    apply_cloud_hostname() { log_call apply_cloud_hostname; }
}

@test "run_firstboot: runs every step and marks first boot done" {
    stub_all_ok
    run run_firstboot "${BATS_TEST_TMPDIR}/done"
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "${CALLS}")" = "apply_setup" ]   # before sshd and os-config start
    file_has "${CALLS}" "resize_root"
    file_has "${CALLS}" "apply_cloud_hostname"
    [ -f "${BATS_TEST_TMPDIR}/done" ]
}

@test "run_firstboot: does nothing once marked done" {
    stub_all_ok
    touch "${BATS_TEST_TMPDIR}/done"
    run run_firstboot "${BATS_TEST_TMPDIR}/done"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

@test "run_firstboot: a failed step leaves first boot unmarked so it retries" {
    stub_all_ok
    # shellcheck disable=SC2329  # invoked by run_firstboot
    resize_root() { return 1; }
    run run_firstboot "${BATS_TEST_TMPDIR}/done"
    [ "$status" -ne 0 ]
    [ ! -e "${BATS_TEST_TMPDIR}/done" ]
    file_has "${CALLS}" "apply_cloud_hostname"   # later steps still run
}

# ---- install_firstboot (build time) ----

@test "install_firstboot: installs the first-boot scripts with brand placeholders replaced" {
    run install_firstboot "${ROOTFS}" kura "Kura" "${REPO_ROOT}/scripts/common"
    [ "$status" -eq 0 ]
    local script
    for script in firstboot.sh firstboot-setup.sh firstboot-setup-check.sh firstboot-disk.sh; do
        [ -x "${ROOTFS}/usr/lib/kura/${script}" ]
        run grep -c "__BRAND" "${ROOTFS}/usr/lib/kura/${script}"
        [ "$output" = "0" ]
    done
    file_has "${ROOTFS}/usr/lib/kura/firstboot.sh" "/var/lib/kura/.firstboot-done"
    file_has "${ROOTFS}/usr/lib/kura/firstboot-setup.sh" 'SETUP_BRAND="${SETUP_BRAND:-kura}"'
}

@test "install_firstboot: first boot runs before sshd, os-config and console logins" {
    run install_firstboot "${ROOTFS}" kura "Kura" "${REPO_ROOT}/scripts/common"
    local unit="${ROOTFS}/usr/lib/systemd/system/kura-firstboot.service"
    file_has "${unit}" "Before=ssh.service kura-config.service systemd-user-sessions.service"
    file_has "${unit}" "ConditionPathExists=!/var/lib/kura/.firstboot-done"
    # A failed step is retried while the device runs, not only at the next boot
    file_has "${unit}" "Restart=on-failure"
    file_has "${unit}" "RestartSec=30"
    file_has "${unit}" "StartLimitIntervalSec=0"
    [ "$(readlink "${ROOTFS}/etc/systemd/system/multi-user.target.wants/kura-firstboot.service")" = \
      "/usr/lib/systemd/system/kura-firstboot.service" ]
}

@test "install_firstboot: SSH keys are generated by their own unit, before sshd, without Docker" {
    run install_firstboot "${ROOTFS}" kura "Kura" "${REPO_ROOT}/scripts/common"
    local unit="${ROOTFS}/usr/lib/systemd/system/kura-ssh-keygen.service"
    # Not before ssh.socket: it is ordered before basic.target, which these
    # units follow, so that would be a cycle once the socket is enabled
    file_has "${unit}" "Before=ssh.service"
    run grep -q "ssh.socket" "${unit}"
    [ "$status" -ne 0 ]
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
