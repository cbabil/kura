#!/bin/bash
# scripts/common/firstboot-password.sh
# An image built with the public default password (admin/admin; passwords.sh
# leaves a default-password mark) gets a random one-time password at first
# boot, before sshd starts: nobody on the network can log in with a
# password they could guess. kura-issue shows it on the device's own screen
# until the owner has changed it (it is expired: the first login must set
# a new one). A password from the imager's setup file replaces it.
#
# Sourced by firstboot-setup.sh, whose LOGIN_UID and write_atomic it uses
# (and firstboot-disk.sh's wipe_file). Defines functions only.

password_state() { echo "${SETUP_ROOT:-}/var/lib/${SETUP_BRAND}/$1"; }

# one_time_password: 12 characters in three groups, no 0/o or 1/l (~59 bits)
one_time_password() {
    local s
    s=$(LC_ALL=C tr -dc 'abcdefghijkmnpqrstuvwxyz23456789' < /dev/urandom | head -c 12)
    echo "${s:0:4}-${s:4:4}-${s:8:4}"
}

# replace_default_password: when the image still has the public default
replace_default_password() {
    local mark user pw
    mark=$(password_state default-password)
    [ -f "${mark}" ] || return 0
    user=$(getent passwd "${LOGIN_UID}" | cut -d: -f1)
    [ -n "${user}" ] || { echo "ERROR: no login user (uid ${LOGIN_UID})" >&2; return 1; }
    pw=$(one_time_password)
    # chpasswd reads it on stdin: never on a command line (auditd records those)
    printf '%s:%s\n' "${user}" "${pw}" | chpasswd && chage -d 0 "${user}" &&
        printf '%s\n' "${pw}" | write_atomic "$(password_state one-time-password)" 600 &&
        rm -f "${mark}"
}

# forget_one_time_password: the owner set their own password
forget_one_time_password() {
    local otp
    otp=$(password_state one-time-password)
    rm -f "$(password_state default-password)"
    if [ -f "${otp}" ]; then wipe_file "${otp}"; rm -f "${otp}"; fi
}
