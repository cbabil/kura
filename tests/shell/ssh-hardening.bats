#!/usr/bin/env bats
# tests/shell/ssh-hardening.bats — tests for lib/ssh.sh, the sshd drop-in
# os-security writes at every boot

setup() {
    load test_helper
    load_security_lib "common"
    load_security_lib "ssh"
    export SSH_DROPIN_DIR="${BATS_TEST_TMPDIR}/sshd_config.d"
    CONF="${SSH_DROPIN_DIR}/99-hardening.conf"
}

@test "apply_ssh_hardening: root by key only, no forwarding, 3 tries" {
    run apply_ssh_hardening
    [ "$status" -eq 0 ]
    for line in "PermitRootLogin prohibit-password" "MaxAuthTries 3" \
                "AllowAgentForwarding no" "AllowTcpForwarding no" "X11Forwarding no"; do
        grep -qxF "${line}" "${CONF}"
    done
}

# Slows password guessing: a short window to log in, and unauthenticated
# connections refused at random from 10 on, all from 60
@test "apply_ssh_hardening: short login window, unauthenticated connections capped" {
    apply_ssh_hardening
    grep -qxF "LoginGraceTime 30" "${CONF}"
    grep -qxF "MaxStartups 10:30:60" "${CONF}"
}
