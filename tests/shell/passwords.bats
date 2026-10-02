#!/usr/bin/env bats
# tests/shell/passwords.bats — scripts/common/passwords.sh sets the build-time
# passwords and expires the login user's, so a shipped image never keeps a
# well-known password past the first login.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."

setup() {
    load test_helper
    unset OS_USER OS_USER_PASSWD OS_USER_PASSWD_EXPIRE OS_ROOT_PASSWD OS_BRAND
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/passwords.sh"
    ROOTFS="${BATS_TEST_TMPDIR}/rootfs"; mkdir -p "${ROOTFS}"
    CALLS="${BATS_TEST_TMPDIR}/calls"; : > "${CALLS}"
    STDIN="${BATS_TEST_TMPDIR}/chpasswd-stdin"
    mount_chroot() { echo "mount $1" >> "${CALLS}"; }
    umount_chroot() { echo "umount $1" >> "${CALLS}"; }
    chroot() {
        shift
        echo "$*" >> "${CALLS}"
        if [ "$1" = "chpasswd" ]; then cat > "${STDIN}"; fi
    }
}

@test "set_passwords: root is locked unless OS_ROOT_PASSWD is set" {
    set_passwords "${ROOTFS}"
    [ "$(cat "${STDIN}")" = "admin:admin" ]
    file_has "${CALLS}" "passwd -l root"
}

@test "set_passwords: the old public root default (the brand name) is refused" {
    OS_ROOT_PASSWD="kura"
    run set_passwords "${ROOTFS}"
    [ "$status" -ne 0 ]
    output_has "OS_ROOT_PASSWD"
    [ ! -s "${CALLS}" ]
}

@test "set_passwords: sets root's and the login user's password through chpasswd's stdin" {
    OS_USER="kiosk"; OS_USER_PASSWD="s3cret"; OS_ROOT_PASSWD="rootpw"
    set_passwords "${ROOTFS}"
    [ "$(cat "${STDIN}")" = "$(printf 'root:rootpw\nkiosk:s3cret')" ]
    # never on a command line, where a quote in the password would break out
    ! grep -q "s3cret\|rootpw" "${CALLS}"
    # a private root password is kept, not locked
    ! grep -q "passwd -l" "${CALLS}"
}

@test "set_passwords: by default admin/admin, expired for the login user only" {
    set_passwords "${ROOTFS}"
    file_has "${STDIN}" "admin:admin"
    file_has "${CALLS}" "chage -d 0 admin"
    # an expired root password breaks cron and su
    ! grep -q "chage.*root" "${CALLS}"
}

@test "set_passwords: OS_USER_PASSWD_EXPIRE=false keeps a private password" {
    OS_USER_PASSWD_EXPIRE="false"; OS_USER_PASSWD="s3cret"
    set_passwords "${ROOTFS}"
    file_has "${STDIN}" "admin:s3cret"
    ! grep -q "chage" "${CALLS}"
}

@test "set_passwords: OS_USER_PASSWD_EXPIRE=false is refused with the default password" {
    OS_USER_PASSWD_EXPIRE="false"
    run set_passwords "${ROOTFS}"
    [ "$status" -ne 0 ]
    output_has "needs a private OS_USER_PASSWD"
    [ ! -s "${CALLS}" ]
}

@test "set_passwords: mounts the chroot around the calls and always unmounts" {
    set_passwords "${ROOTFS}"
    [ "$(head -1 "${CALLS}")" = "mount ${ROOTFS}" ]
    [ "$(tail -1 "${CALLS}")" = "umount ${ROOTFS}" ]
}

@test "set_passwords: fails when chpasswd fails, and still unmounts" {
    chroot() { shift; echo "$*" >> "${CALLS}"; [ "$1" != "chpasswd" ]; }
    run set_passwords "${ROOTFS}"
    [ "$status" -ne 0 ]
    [ "$(tail -1 "${CALLS}")" = "umount ${ROOTFS}" ]
}
