#!/usr/bin/env bats
# tests/shell/one-time-password.bats — scripts/common/firstboot-password.sh:
# an image built with the public default password (admin/admin) gets a
# random one-time password at first boot, before sshd starts, so nobody on
# the network can log in with a password they could guess. It is shown on
# the device's own screen (kura-issue) and must be changed at first login.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
PW_RE='^[a-km-np-z2-9]{4}-[a-km-np-z2-9]{4}-[a-km-np-z2-9]{4}$'

setup() {
    load test_helper
    SETUP_ROOT="${BATS_TEST_TMPDIR}/root"
    SETUP_BRAND=kura
    export SETUP_ROOT SETUP_BRAND
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/firstboot-setup.sh"
    CALLS="${BATS_TEST_TMPDIR}/calls"; : > "${CALLS}"
    STATE="${SETUP_ROOT}/var/lib/kura"
    mkdir -p "${STATE}"
    getent() { [ "$1:$2" = passwd:1000 ] && echo "admin:x:1000:1000::/home/admin:/bin/bash"; }
    chpasswd() { cat > "${BATS_TEST_TMPDIR}/chpasswd-stdin"; log_call "chpasswd $*"; }
    chage() { log_call "chage $*"; }
}

@test "one_time_password: 12 easy-to-read characters, different every time" {
    local a b
    a=$(one_time_password); b=$(one_time_password)
    [[ "${a}" =~ ${PW_RE} ]]
    [ "${a}" != "${b}" ]
}

@test "replace_default_password: random password, must be changed at first login" {
    touch "${STATE}/default-password"
    run replace_default_password
    [ "$status" -eq 0 ]
    local pw
    pw=$(cat "${STATE}/one-time-password")
    [[ "${pw}" =~ ${PW_RE} ]]
    [ "$(cat "${BATS_TEST_TMPDIR}/chpasswd-stdin")" = "admin:${pw}" ]
    file_has "${CALLS}" "chage -d 0 admin"
    [ "$(file_mode "${STATE}/one-time-password")" = "600" ]
    [ ! -e "${STATE}/default-password" ]
    # on stdin only, never on a command line (the audit log records those)
    ! grep -qF "${pw}" "${CALLS}"
}

@test "replace_default_password: an image with a private password is left alone" {
    run replace_default_password
    [ "$status" -eq 0 ]
    [ ! -s "${CALLS}" ]
    [ ! -e "${STATE}/one-time-password" ]
}

@test "forget_one_time_password: the setup file's password replaces it" {
    touch "${STATE}/default-password"
    echo "abcd-efgh-jkmn" > "${STATE}/one-time-password"
    forget_one_time_password
    [ ! -e "${STATE}/default-password" ]
    [ ! -e "${STATE}/one-time-password" ]
}
