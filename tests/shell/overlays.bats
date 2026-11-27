#!/usr/bin/env bats
# tests/shell/overlays.bats — every image's files belong to an account of the
# image. rsync -a kept the owner of the checkout (the CI runner's ID 1001),
# which made / and /etc belong to whichever account later got that ID.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() { load test_helper; }

@test "apply_overlays: every rsync into the rootfs sets root as the owner" {
    local lines
    lines=$(grep -nE '^[[:space:]]*rsync ' "${REPO_ROOT}/build.sh")
    [ -n "${lines}" ]
    run grep -vF -- '--chown=0:0' <<< "${lines}"
    [ -z "$output" ]
}

@test "the PC and Pi images check their owners (verify_rootfs, before the image is made)" {
    file_has "${REPO_ROOT}/scripts/common/verify-rootfs.sh" 'verify_owners "${rootfs}" || status=1'
    file_has "${REPO_ROOT}/build.sh" 'verify_rootfs "${ROOTFS}" "${BRAND}"'
}

@test "the Docker image checks its owners before the tarball" {
    local script="${REPO_ROOT}/scripts/docker/create-image.sh"
    [ "$(grep -n 'verify_owners "${DOCKER_ROOTFS}"' "${script}" | cut -d: -f1)" -lt \
      "$(grep -n '^tar -C' "${script}" | cut -d: -f1)" ]
}

@test "the PC installer's initrd checks that root owns it before packing" {
    local script="${REPO_ROOT}/scripts/pc-installer/build-initrd.sh"
    [ "$(grep -n '! -user 0 -o ! -group 0' "${script}" | head -1 | cut -d: -f1)" -lt \
      "$(grep -n 'cpio -o' "${script}" | cut -d: -f1)" ]
}

# root_owns_system (tests/boot): its commands reach the device's shell whole.
# ssh_run runs them in a local shell, the way the guest's would; sudo, stat
# and find answer from STAT and FOUND, and record what they were given.
boot_device() {
    REPORT="${BATS_TEST_TMPDIR}/report" LOGIN_PASS=pw BRAND=kura
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/tests/boot/boot-checks.sh"
    bin="${BATS_TEST_TMPDIR}/bin"
    mkdir -p "${bin}"
    printf '#!/bin/sh\nwhile [ "$1" != stat ] && [ "$1" != find ]; do shift; done\nexec "$@"\n' > "${bin}/sudo"
    printf '#!/bin/sh\necho "$*" > "%s/stat.args"\nprintf "%%s\\n" "$STAT"\n' "${BATS_TEST_TMPDIR}" > "${bin}/stat"
    printf '#!/bin/sh\necho "$*" > "%s/find.args"\n[ -z "$FOUND" ] || echo "$FOUND"\n' "${BATS_TEST_TMPDIR}" > "${bin}/find"
    chmod +x "${bin}"/*
    ssh_run() { PATH="${bin}:${PATH}" sh -c "$*"; }
}
ROOTS=$'0:0 /\n0:0 /etc\n0:0 /usr\n0:0 /usr/share\n0:0 /etc/kura\n0:0 /etc/plymouth/plymouthd.conf\n0:0 /usr/share/plymouth/themes/kura\n0:0 /usr/share/grub/themes/kura'

@test "root_owns_system: passes when root owns them all and every owner has an account" {
    boot_device
    STAT="${ROOTS}" FOUND="" run root_owns_system
    [ "$status" -eq 0 ]
    [ "$(cat "${BATS_TEST_TMPDIR}/find.args")" = "/ -xdev ( -nouser -o -nogroup ) -print" ]
    [ "$(cat "${BATS_TEST_TMPDIR}/stat.args")" = "-c %u:%g %n / /etc /usr /usr/share /etc/kura /etc/plymouth/plymouthd.conf /usr/share/plymouth/themes/kura /usr/share/grub/themes/kura" ]
}

@test "root_owns_system: fails and reports / owned by 1001" {
    boot_device
    STAT="${ROOTS/0:0 \//1001:1001 /}" FOUND="" run root_owns_system
    [ "$status" -eq 1 ]
    file_has "${REPORT}" "not root's: 1001:1001 /"
}

@test "root_owns_system: fails and reports a file whose owner has no account" {
    boot_device
    STAT="${ROOTS}" FOUND="/etc/stray" run root_owns_system
    [ "$status" -eq 1 ]
    file_has "${REPORT}" "no account: /etc/stray"
}

@test "root_owns_system: fails when a path is missing (stat names fewer)" {
    boot_device
    STAT="$(head -n 7 <<< "${ROOTS}")" FOUND="" run root_owns_system
    [ "$status" -eq 1 ]
}
