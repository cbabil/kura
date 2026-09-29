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
}

@test "verify_rootfs: passes a complete image" {
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 0 ]
}

@test "verify_rootfs: required files cover Docker, Tomo, first boot and the supervisor" {
    run rootfs_required_files kura
    output_has "usr/libexec/docker/cli-plugins/docker-compose"
    output_has "opt/tomo/dist/index.js"
    output_has "usr/share/kura/images/traefik.tar"
    output_has "usr/lib/kura/firstboot.sh"
    output_has "opt/kura-supervisor/src/index.js"
}

@test "verify_rootfs: fails and names a missing file" {
    rm "${ROOTFS}/opt/tomo/dist/index.js"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "MISSING: /opt/tomo/dist/index.js"
}

@test "verify_rootfs: fails and names a missing enable link" {
    rm "${ROOTFS}/etc/systemd/system/multi-user.target.wants/tomod.service"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "MISSING symlink: /etc/systemd/system/multi-user.target.wants/tomod.service"
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
    rm "${ROOTFS}/usr/bin/node"
    touch "${ROOTFS}/etc/ssh/ssh_host_rsa_key"
    run verify_rootfs "${ROOTFS}" kura
    [ "$status" -eq 1 ]
    output_has "MISSING: /usr/bin/node"
    output_has "SSH host keys"
}
