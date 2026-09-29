#!/usr/bin/env bats
# tests/shell/x86-live-storage.bats — the x86 live ISO keeps container storage
# in RAM: its root is an overlay, and Docker/containerd can't stack an overlay
# on an overlay ("invalid argument" when creating any container).

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"
    mkdir -p "${ROOTFS}/usr/lib/systemd/system"
    run "${REPO_ROOT}/scripts/x86_64/customize-rootfs.sh" "${ROOTFS}"
    [ "$status" -eq 0 ]
}

@test "live ISO: containerd and Docker storage are tmpfs mounts, before both daemons" {
    local unit
    for unit in var-lib-containerd.mount var-lib-docker.mount; do
        local f="${ROOTFS}/usr/lib/systemd/system/${unit}"
        file_has "${f}" "Type=tmpfs"
        file_has "${f}" "Before=containerd.service docker.service"
    done
    file_has "${ROOTFS}/usr/lib/systemd/system/var-lib-containerd.mount" "Where=/var/lib/containerd"
    file_has "${ROOTFS}/usr/lib/systemd/system/var-lib-docker.mount" "Where=/var/lib/docker"
}

@test "live ISO: the RAM mounts apply only when booted live" {
    file_has "${ROOTFS}/usr/lib/systemd/system/var-lib-containerd.mount" "ConditionKernelCommandLine=boot=live"
    file_has "${ROOTFS}/usr/lib/systemd/system/var-lib-docker.mount" "ConditionKernelCommandLine=boot=live"
}

@test "live ISO: the RAM mounts are enabled" {
    local wants="${ROOTFS}/etc/systemd/system/local-fs.target.wants"
    [ "$(readlink "${wants}/var-lib-containerd.mount")" = "/usr/lib/systemd/system/var-lib-containerd.mount" ]
    [ "$(readlink "${wants}/var-lib-docker.mount")" = "/usr/lib/systemd/system/var-lib-docker.mount" ]
}
