#!/usr/bin/env bats
# tests/shell/first-login.bats — tests/boot/first-login.exp answers the forced
# password change at first login, and fails if the guest never demands it.

SCRIPT="${BATS_TEST_DIRNAME}/../boot/first-login.exp"

setup() {
    load test_helper
    command -v expect >/dev/null || skip "expect is not installed"
    BIN="${BATS_TEST_TMPDIR}/bin"; mkdir -p "${BIN}"
    export PATH="${BIN}:${PATH}" ANSWERS="${BATS_TEST_TMPDIR}/answers"
}

# fake_ssh <body>: an ssh that plays the guest's side of the conversation
fake_ssh() { printf '#!/bin/bash\n%s\n' "$1" > "${BIN}/ssh"; chmod +x "${BIN}/ssh"; }

EXPIRED='
ask() { printf "%s " "$1"; read -r reply; echo "${reply}" >> "${ANSWERS}"; }
ask "admin@127.0.0.1'"'"'s password:"
echo "You are required to change your password immediately (administrator enforced)."
ask "Current password:"
ask "New password:"
ask "Retype new password:"
echo "passwd: password updated successfully"'

@test "first-login: answers the forced change with the old, then the new password twice" {
    fake_ssh "${EXPIRED}"
    run "${SCRIPT}" 2222 admin admin N3w-pass
    [ "$status" -eq 0 ]
    [ "$(tr '\n' ' ' < "${ANSWERS}")" = "admin admin N3w-pass N3w-pass " ]
}

@test "first-login: fails when the guest opens a shell without demanding a new password" {
    # the session stays open, as a real shell would: the script must not wait it out
    fake_ssh 'printf "admin@127.0.0.1'"'"'s password: "; read -r _; printf "admin@kura:~\$ "; exec sleep 20'
    run "${SCRIPT}" 2222 admin admin N3w-pass
    [ "$status" -ne 0 ]
    output_has "got a shell before"
}

@test "first-login: fails when the new password is not accepted" {
    fake_ssh "${EXPIRED/passwd: password updated successfully/passwd: Authentication token manipulation error}"
    run "${SCRIPT}" 2222 admin admin N3w-pass
    [ "$status" -ne 0 ]
    output_has "without confirmation"
}
