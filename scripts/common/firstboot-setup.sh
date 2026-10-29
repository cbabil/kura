#!/bin/bash
# scripts/common/firstboot-setup.sh
# First-boot setup handed over by an imager (Etchwise): __BRAND__-setup.json at
# the root of the boot partition. Sourced by firstboot.sh; installed next to it
# by install-firstboot.sh, which replaces the placeholders. Defines functions
# only.
#
# Format (every key optional except version; a key left out keeps the image's
# default):
#   {"version":1, "hostname":"kura-01",
#    "user":{"name":"chris","passwordHash":"$y$..."},
#    "ssh":{"enabled":true,"passwordAuth":false,"authorizedKeys":["ssh-ed25519 ..."]},
#    "wifi":{"ssid":"Home","psk":"<8-63 chars or 64 hex>","hidden":false,"country":"FR"},
#    "timezone":"Europe/Paris", "keyboard":"fr"}
#
# The file holds a password hash and the Wi-Fi key, so it is overwritten and
# deleted once applied, and also when it is invalid (then the image's
# defaults stay). A bad Wi-Fi section skips the Wi-Fi only. The file is kept
# when a step fails, so first boot retries it. Secrets never go on a command
# line (auditd records every execve) and messages never include values.

# shellcheck disable=SC2016  # jq and awk programs are single-quoted on purpose

SETUP_BRAND="${SETUP_BRAND:-__BRAND__}"
SETUP_ROOT="${SETUP_ROOT:-}"          # tests write under a scratch root
SETUP_FILE="${SETUP_BRAND}-setup.json"
LOGIN_UID=1000                        # the image's login user and group (customize-rootfs.sh)

# validate_setup, validate_wifi and their helpers; boot_partition, with_mount
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/firstboot-setup-check.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/firstboot-disk.sh"
# replace_default_password, forget_one_time_password
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/firstboot-password.sh"

sshd_conf() { echo "${SETUP_ROOT}/etc/ssh/sshd_config.d/10-${SETUP_BRAND}.conf"; }

# write_atomic <file> <mode>: stdin to <file>, never visible half-written or
# with a wider mode
write_atomic() {
    (umask 077 && cat > "$1.new") && chmod "$2" "$1.new" && mv "$1.new" "$1"
}

# edit_file <file> <awk-program> [awk args...]: rewrite in place, atomically
edit_file() {
    local file="$1" out
    shift
    out=$(awk "$@" "${file}") && printf '%s\n' "${out}" | write_atomic "${file}" 644
}

# edit_config <jq-filter> [jq args...]: update os-config's config.json, which
# os-config applies (hostname with /etc/hosts, Wi-Fi connections)
edit_config() {
    local filter="$1" cfg="${SETUP_ROOT}/etc/${SETUP_BRAND}/config.json" out
    shift
    out=$(jq "$@" "${filter}" "${cfg}") && printf '%s\n' "${out}" | write_atomic "${cfg}" 600
}

setup_hostname() { edit_config '.hostname = $h' --arg h "$1"; }

# setup_user <name> <crypt-hash|"">: rename the login user and its group, set
# the password and lift the forced change. Each part checks the current
# state, so a retry finishes a half-done rename.
setup_user() {
    local name="$1" hash="$2" old group
    old=$(getent passwd "${LOGIN_UID}" | cut -d: -f1)
    [ -n "${old}" ] || { setup_error "no login user (uid ${LOGIN_UID})"; return 1; }
    if [ "${name}" != "${old}" ]; then
        usermod -l "${name}" -d "/home/${name}" -m "${old}" || return 1
    fi
    group=$(getent group "${LOGIN_UID}" | cut -d: -f1)
    if [ -n "${group}" ] && [ "${group}" != "${name}" ]; then
        groupmod -n "${name}" "${group}" || return 1
    fi
    edit_file "$(sshd_conf)" -v u="${name}" '/^Match User / { print "Match User " u; next } { print }' ||
        return 1
    [ -n "${hash}" ] || return 0
    # chpasswd reads the hash on stdin; chage -d -1 clears the forced change
    # without trusting the clock (a Pi has no RTC)
    printf '%s:%s\n' "${name}" "${hash}" | chpasswd -e && chage -d -1 "${name}" &&
        forget_one_time_password
}

# setup_ssh <enabled> <password-auth> [keys...]
setup_ssh() {
    local enabled="$1" pwauth="$2" user home dir
    shift 2
    if [ "${enabled}" = "false" ]; then
        systemctl --no-block disable --now ssh.service ssh.socket || return 1
    fi
    if [ "${pwauth}" = "false" ]; then   # drop the login user's Match block
        edit_file "$(sshd_conf)" '/^Match / { skip = 1; next } skip && /^[[:space:]]/ { next } { skip = 0; print }' ||
            return 1
    fi
    [ "$#" -gt 0 ] || return 0
    IFS=: read -r user _ _ _ _ home _ < <(getent passwd "${LOGIN_UID}")
    dir="${SETUP_ROOT}${home}/.ssh"
    install -d -m 0700 "${dir}" &&
    printf '%s\n' "$@" | write_atomic "${dir}/authorized_keys" 600 &&
    chown -R "${user}:" "${dir}"
}

# setup_wifi_config <ssid> <psk> <hidden> <country|"">: the key reaches jq
# through the environment, not argv. The country takes effect when cfg80211
# next loads (next boot); until then the world domain applies.
setup_wifi_config() {
    SETUP_PSK="$2" edit_config '.networkConfig.wifi.enable = true
        | .networkConfig.wifi.defaultInterface //= "wlan0"
        | .networkConfig.wifi.networks = [{ssid: $s, psk: $ENV.SETUP_PSK, hidden: $h}]' \
        --arg s "$1" --argjson h "${3:-false}" || return 1
    [ -n "$4" ] || return 0
    install -d "${SETUP_ROOT}/etc/modprobe.d" &&
    printf 'options cfg80211 ieee80211_regdom=%s\n' "$4" |
        write_atomic "${SETUP_ROOT}/etc/modprobe.d/cfg80211.conf" 644
}

setup_timezone() {
    if [ ! -f "${SETUP_ROOT}/usr/share/zoneinfo/$1" ]; then
        echo "WARNING: setup: unknown time zone $1; keeping UTC" >&2
        return 0
    fi
    ln -sf "/usr/share/zoneinfo/$1" "${SETUP_ROOT}/etc/localtime" &&
    echo "$1" | write_atomic "${SETUP_ROOT}/etc/timezone" 644
}

# setup_keyboard <layout>: read by console-setup (from the next boot)
setup_keyboard() {
    install -d "${SETUP_ROOT}/etc/default" &&
    printf 'XKBMODEL="pc105"\nXKBLAYOUT="%s"\nXKBVARIANT=""\nXKBOPTIONS=""\nBACKSPACE="guess"\n' "$1" |
        write_atomic "${SETUP_ROOT}/etc/default/keyboard" 644
}

# apply_wifi <file>: a bad Wi-Fi section is skipped with a warning
apply_wifi() {
    local f="$1"
    if ! validate_wifi "${f}"; then
        echo "WARNING: setup: Wi-Fi settings skipped; the rest is applied" >&2
        return 0
    fi
    setup_wifi_config "$(setup_get "${f}" .wifi.ssid)" "$(setup_get "${f}" .wifi.psk)" \
        "$(jq -r '.wifi.hidden == true' "${f}")" "$(setup_get "${f}" .wifi.country)"
}

# apply_setup_file <file>: apply a validated file, user before SSH (keys go
# to the final user)
apply_setup_file() {
    local f="$1" v key keys=()
    v=$(setup_get "${f}" .hostname)
    [ -z "${v}" ] || setup_hostname "${v}" || return 1
    if setup_has "${f}" user; then
        setup_user "$(setup_get "${f}" .user.name)" "$(setup_get "${f}" .user.passwordHash)" || return 1
    fi
    if setup_has "${f}" ssh; then
        while IFS= read -r key; do keys+=("${key}"); done < <(jq -r '.ssh.authorizedKeys[]?' "${f}")
        setup_ssh "$(jq -r '.ssh.enabled != false' "${f}")" "$(jq -r '.ssh.passwordAuth != false' "${f}")" \
            ${keys[@]+"${keys[@]}"} || return 1
    fi
    if setup_has "${f}" wifi; then
        apply_wifi "${f}" || return 1
    fi
    v=$(setup_get "${f}" .timezone)
    [ -z "${v}" ] || setup_timezone "${v}" || return 1
    v=$(setup_get "${f}" .keyboard)
    [ -z "${v}" ] || setup_keyboard "${v}" || return 1
}

# remove_setup_file <file>
remove_setup_file() {
    wipe_file "$1"
    rm -f "$1" || { setup_error "could not delete ${SETUP_FILE}"; return 1; }
}

# record_setup_status <text>: the outcome the login screen shows (kura-issue)
record_setup_status() {
    install -d "${SETUP_ROOT}/var/lib/${SETUP_BRAND}"
    printf '%s\n' "$1" | write_atomic "${SETUP_ROOT}/var/lib/${SETUP_BRAND}/setup-status" 644
}

# apply_setup_dir <mounted-boot-dir>
apply_setup_dir() {
    local f="$1/${SETUP_FILE}"
    [ -f "${f}" ] || return 0
    if ! validate_setup "${f}"; then
        record_setup_status "ignored: ${SETUP_LAST_ERROR}"
        setup_error "${SETUP_FILE} ignored; the image's defaults stay"
        remove_setup_file "${f}"
        return
    fi
    SETUP_LAST_ERROR=""
    if ! apply_setup_file "${f}"; then
        # Not every step names its failure; the journal has the details
        record_setup_status "incomplete, retrying: ${SETUP_LAST_ERROR:-a step failed (journalctl -u ${SETUP_BRAND}-firstboot)}"
        setup_error "${SETUP_FILE} not fully applied; first boot will retry"
        return 1
    fi
    remove_setup_file "${f}" && record_setup_status "applied" &&
        echo "Setup from ${SETUP_FILE} applied."
}

# apply_setup: apply the setup file from the boot partition, which is never
# mounted otherwise. No FAT boot partition or no file: nothing to do.
apply_setup() {
    local dev status=0
    dev=$(boot_partition) || return 0
    is_fat_partition "${dev}" || return 0
    with_mount "${dev}" apply_setup_dir -t vfat -o nosuid,nodev,noexec,umask=077 || status=$?
    [ "${status}" -ne 2 ] || { setup_error "could not mount the boot partition ${dev}"; return 1; }
    return "${status}"
}
