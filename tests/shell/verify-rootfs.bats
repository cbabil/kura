#!/usr/bin/env bats
# tests/shell/verify-rootfs.bats — tests for scripts/common/verify-rootfs.sh
# (fail-fast checks run on every image before the artifact is created)

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/verify-rootfs.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    make_complete_rootfs
}

# A rootfs with every required file and enable link, and no baked identity.
make_complete_rootfs() {
    local f
    for f in $(rootfs_required_files kura); do
        mkdir -p "$(dirname "${ROOTFS}/${f}")"
        touch "${ROOTFS}/${f}"
    done
    for f in $(rootfs_required_links kura); do
        mkdir -p "$(dirname "${ROOTFS}/${f}")"
        ln -sf "/usr/lib/systemd/system/$(basename "${f}")" "${ROOTFS}/${f}"
    done
    mkdir -p "${ROOTFS}/etc/ssh"
    : > "${ROOTFS}/etc/machine-id"
    printf 'root:x:0:\nsudo:x:27:admin\n' > "${ROOTFS}/etc/group"
    printf 'root:!*:20000:0:99999:7:::\nadmin:$y$hash:0:0:99999:7:::\n' > "${ROOTFS}/etc/shadow"
}

@test "verify_rootfs: passes a complete image" {
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 0 ]
}

@test "verify_rootfs: required files cover Docker, first boot and the OS services" {
    run rootfs_required_files kura
    output_has "usr/libexec/docker/cli-plugins/docker-compose"
    output_has "usr/lib/kura/firstboot.sh"
    output_has "usr/lib/kura/firstboot-setup.sh"
    output_has "usr/bin/kura-config"
}

@test "verify_rootfs: fails when a removed component is back (Tomo, the supervisor, Bun)" {
    local f
    for f in opt/tomo usr/local/bin/bun opt/kura-supervisor \
             usr/lib/systemd/system/kura-supervisor.service; do
        make_complete_rootfs
        mkdir -p "$(dirname "${ROOTFS}/${f}")"
        touch "${ROOTFS}/${f}"
        run verify_rootfs "${ROOTFS}" kura
        [ "$status" -eq 1 ]
        output_has "UNEXPECTED: /${f}"
        rm -rf "${ROOTFS:?}/${f}"
    done
}

@test "verify_rootfs: fails and names a missing file" {
    rm "${ROOTFS}/usr/lib/kura/firstboot.sh"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "MISSING: /usr/lib/kura/firstboot.sh"
}

@test "verify_rootfs: fails and names a missing enable link" {
    rm "${ROOTFS}/etc/systemd/system/multi-user.target.wants/docker.service"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "MISSING symlink: /etc/systemd/system/multi-user.target.wants/docker.service"
}

@test "verify_rootfs: an enable link must be a symlink, not a file" {
    local link="${ROOTFS}/etc/systemd/system/multi-user.target.wants/docker.service"
    rm "${link}"
    touch "${link}"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
}

@test "verify_rootfs: fails when SSH host keys are baked in" {
    touch "${ROOTFS}/etc/ssh/ssh_host_ed25519_key"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "SSH host keys"
}

@test "verify_rootfs: fails when the machine ID is baked in" {
    echo "0123456789abcdef0123456789abcdef" > "${ROOTFS}/etc/machine-id"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "machine-id"
}

@test "verify_rootfs: reports every problem, not just the first" {
    rm "${ROOTFS}/usr/bin/docker"
    touch "${ROOTFS}/etc/ssh/ssh_host_rsa_key"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "MISSING: /usr/bin/docker"
    output_has "SSH host keys"
}

@test "verify_rootfs: fails when the login user's password is not expired" {
    sed -i.bak 's/^admin:\([^:]*\):0:/admin:\1:20000:/' "${ROOTFS}/etc/shadow"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -ne 0 ]
    output_has "password is not expired"
}

@test "verify_rootfs: an unexpired password is fine when the build opted out" {
    sed -i.bak 's/^admin:\([^:]*\):0:/admin:\1:20000:/' "${ROOTFS}/etc/shadow"
    OS_USER_PASSWD_EXPIRE="false" run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 0 ]
}

@test "verify_rootfs: fails when root has a password nobody asked for" {
    sed -i.bak 's/^root:[^:]*:/root:$y$hash:/' "${ROOTFS}/etc/shadow"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -ne 0 ]
    output_has "root's password is not locked"
}

@test "verify_rootfs: a root password is fine when OS_ROOT_PASSWD set one" {
    sed -i.bak 's/^root:[^:]*:/root:$y$hash:/' "${ROOTFS}/etc/shadow"
    OS_ROOT_PASSWD="rootpw" run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 0 ]
}

@test "verify_rootfs: fails when the login user has no sudo (root is locked: no way in)" {
    printf 'sudo:x:27:\n' > "${ROOTFS}/etc/group"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -ne 0 ]
    output_has "not in the sudo group"
}

@test "verify_rootfs: fails when an APT source skips signature checks (trusted=yes)" {
    mkdir -p "${ROOTFS}/etc/apt/sources.list.d"
    echo "deb [trusted=yes] http://example.com/debian trixie main" > "${ROOTFS}/etc/apt/sources.list.d/x.list"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "trusted=yes"
}

@test "verify_rootfs: fails on trusted: yes in a deb822 source too" {
    mkdir -p "${ROOTFS}/etc/apt/sources.list.d"
    printf 'Types: deb\nURIs: http://example.com\nTrusted: yes\n' > "${ROOTFS}/etc/apt/sources.list.d/x.sources"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
}

@test "verify_rootfs: updates and the clock sync are required" {
    rootfs_required_files kura | grep -qx "usr/bin/unattended-upgrade"
    rootfs_required_files kura | grep -qx "etc/apt/apt.conf.d/20auto-upgrades"
    rootfs_required_files kura | grep -qx "usr/lib/systemd/systemd-timesyncd"
    rootfs_required_links kura | grep -qx "etc/systemd/system/timers.target.wants/apt-daily-upgrade.timer"
    rootfs_required_links kura | grep -qx "etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service"
}
