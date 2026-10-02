#!/bin/bash
# scripts/common/passwords.sh
# Sets the build-time passwords inside the rootfs.
#
#   OS_ROOT_PASSWD            root's console password (root SSH is key-only).
#                             Default: none, root's password is locked and
#                             the login user's sudo is the way to root. The
#                             former public default, the brand name, is refused.
#   OS_USER / OS_USER_PASSWD  the login user and its password (default admin/admin)
#   OS_USER_PASSWD_EXPIRE     "false" keeps the login user's password valid;
#                             refused with the default password. Default:
#                             expired, so the first SSH or console login must
#                             set a new one and no image keeps a public password.
#
# Source this file; it defines functions only. set_passwords expects
# mount_chroot and umount_chroot (build.sh).

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/brand-defaults.sh"

# login_password_expires: true unless the build opted out.
login_password_expires() { [ "${OS_USER_PASSWD_EXPIRE:-true}" != "false" ]; }

# set_passwords <rootfs>
set_passwords() {
    local rootfs="$1" rc=0 root="${OS_ROOT_PASSWD:-}"
    local user="${OS_USER:-${DEFAULT_USER}}" passwd="${OS_USER_PASSWD:-${DEFAULT_USER_PASSWD}}"

    if ! login_password_expires && [ "${passwd}" = "${DEFAULT_USER_PASSWD}" ]; then
        echo "ERROR: OS_USER_PASSWD_EXPIRE=false needs a private OS_USER_PASSWD, not the default" >&2
        return 1
    fi
    if [ "${root}" = "${OS_BRAND:-${DEFAULT_BRAND}}" ]; then
        echo "ERROR: OS_ROOT_PASSWD is the old public default; unset it (root is locked) or choose a private one" >&2
        return 1
    fi

    mount_chroot "${rootfs}"
    # On stdin, never a command line: a quote in a password can't break out.
    # Only the login user expires: an expired root password breaks cron and su.
    {
        [ -z "${root}" ] || printf 'root:%s\n' "${root}"
        printf '%s:%s\n' "${user}" "${passwd}"
    } | chroot "${rootfs}" chpasswd \
        && { [ -n "${root}" ] || chroot "${rootfs}" passwd -l root; } \
        && { ! login_password_expires || chroot "${rootfs}" chage -d 0 "${user}"; } \
        || rc=1
    umount_chroot "${rootfs}"
    return "${rc}"
}

# shadow_entry <rootfs> <user> <field> <regex>
# True if that user's shadow field matches.
shadow_entry() {
    awk -F: -v u="$2" -v f="$3" -v re="$4" '$1 == u && $f ~ re { ok = 1 } END { exit !ok }' \
        "$1/etc/shadow" 2>/dev/null
}

# login_password_expired <rootfs>
# True if the login user must change its password at next login (last-change
# field 0), or the build opted out.
login_password_expired() {
    login_password_expires || return 0
    shadow_entry "$1" "${OS_USER:-${DEFAULT_USER}}" 3 '^0$'
}

# root_password_locked <rootfs>
# True if root has no usable password, or the build set one.
root_password_locked() {
    [ -z "${OS_ROOT_PASSWD:-}" ] || return 0
    shadow_entry "$1" root 2 '^[!*]'
}

# login_user_has_sudo <rootfs>
# With root locked, the login user's sudo is the only way to root.
login_user_has_sudo() {
    grep -Eq "^sudo:[^:]*:[^:]*:(.*,)?${OS_USER:-${DEFAULT_USER}}(,.*)?\$" "$1/etc/group" 2>/dev/null
}
