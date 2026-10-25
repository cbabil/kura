#!/bin/bash
# tests/boot/boot-checks.sh
# Checks run from the host by boot-test.sh against the booted guest. Source
# this file; it uses boot-test.sh's settings (REPORT, OUT, SSH_PORT,
# LOGIN_USER, LOGIN_PASS, DEFAULT_PASS, KEY, BRAND, WAIT_SECS).
#
# QEMU's user networking forwards IPv4 only: use 127.0.0.1, never localhost
# (ssh-keyscan stops at localhost's IPv6 address).

report() { echo "$*" | tee -a "${REPORT}"; }

# wait_for <description> <command...>: poll every 10 s until the command
# succeeds or WAIT_SECS pass.
wait_for() {
    local what="$1" deadline=$(( SECONDS + WAIT_SECS ))
    shift
    until "$@"; do
        if [ "${SECONDS}" -ge "${deadline}" ]; then
            report "  timed out after ${WAIT_SECS}s waiting for: ${what}"
            return 1
        fi
        sleep 10
    done
}

# check <name> <command...>: record PASS/FAIL without stopping the run.
# shellcheck disable=SC2034  # FAILED is read by boot-test.sh
FAILED=0
# shellcheck disable=SC2034
check() {
    local name="$1"
    shift
    if "$@"; then report "PASS ${name}"; else report "FAIL ${name}"; FAILED=1; fi
}

SSH_OPTS=(-p "${SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o ConnectTimeout=10 -o LogLevel=ERROR)

# login_ssh: the ssh command (without its destination) for the login user,
# by key when the setup file installed one, else by password; an array, so
# timeout can run it
login_ssh() {
    if [ -f "${KEY}" ]; then
        LOGIN_SSH=(ssh "${SSH_OPTS[@]}" -i "${KEY}" -o IdentitiesOnly=yes)
    else
        LOGIN_SSH=(sshpass -p "${LOGIN_PASS}" ssh "${SSH_OPTS[@]}")
    fi
}

# ssh_run <command>: as the login user
ssh_run() { login_ssh; "${LOGIN_SSH[@]}" "${LOGIN_USER}@127.0.0.1" "$@"; }

# sudo_run <command>: one command as root (password on stdin), passed to the
# guest shell as-is
sudo_run() { ssh_run "echo '${LOGIN_PASS}' | sudo -S -p '' $1"; }

ssh_listening() { ssh-keyscan -p "${SSH_PORT}" -T 5 127.0.0.1 2>/dev/null | grep -q .; }

# The default password must only reach a forced password change (first-login.exp
# fails if it gets a shell); from then on LOGIN_PASS is the password.
first_login_changes_password() {
    "$(dirname "$0")/first-login.exp" "${SSH_PORT}" "${LOGIN_USER}" "${DEFAULT_PASS}" "${LOGIN_PASS}" \
        > "${OUT}/first-login.log" 2>&1 || return 1
    ssh_run true
}

# The setup file turned password logins off: the right password must fail
password_login_refused() {
    ! sshpass -p "${LOGIN_PASS}" ssh "${SSH_OPTS[@]}" -o PubkeyAuthentication=no \
        "${LOGIN_USER}@127.0.0.1" true 2>/dev/null
}

setup_applied() {
    [ "$(ssh_run hostname)" = "kura-ci" ] &&
    [ "$(ssh_run readlink /etc/localtime)" = "/usr/share/zoneinfo/Europe/Paris" ] &&
    [ "$(sudo_run "jq -r '.networkConfig.wifi.networks[0].ssid' /etc/${BRAND}/config.json")" = "CIWifi" ] &&
    sudo_run "test -s /etc/NetworkManager/system-connections/CIWifi.nmconnection"
}

setup_file_gone() { sudo_run "test ! -e /boot/efi/${BRAND}-setup.json"; }

secure_boot_on() { sudo_run "dmesg" | grep -q "Secure boot enabled"; }

# /boot/efi is mounted from fstab, and the APT hook's sync finds nothing newer
efi_partition_current() {
    ssh_run "findmnt -no FSTYPE /boot/efi" | grep -qx vfat &&
    [ -z "$(sudo_run "/usr/lib/${BRAND}/sync-efi.sh")" ]
}

# root_grown <image-bytes>: the root filesystem is now larger than the whole
# image was (the disk was grown before boot) and accepts writes
root_grown() {
    local size
    size=$(ssh_run "df -B1 --output=size / | tail -1" | tr -d ' ')
    report "  root filesystem: ${size} bytes (image: $1)"
    [ "${size}" -gt "$1" ] && ssh_run "touch /var/tmp/boot-test && rm /var/tmp/boot-test"
}

# systemctl is-active exits 0 if ANY listed unit is active, so check each
# unit's own state line.
services_active() {
    local states
    states=$(ssh_run systemctl is-active docker "${BRAND}-firstboot" "${BRAND}-ssh-keygen" \
        "${BRAND}-config" || true)
    # shellcheck disable=SC2001  # indent every line, not one substitution
    sed 's/^/  /' <<< "${states}" >> "${REPORT}"
    [ "$(echo "${states}" | grep -cx active)" -eq 4 ]
}

docker_answers() { sudo_run "docker info --format '{{.ServerVersion}}'" | grep -q .; }

record_identity() {
    local host_key machine_id
    host_key=$(ssh-keyscan -p "${SSH_PORT}" -t ed25519 127.0.0.1 2>/dev/null \
        | ssh-keygen -lf - | awk '{print $2}')
    machine_id=$(ssh_run cat /etc/machine-id)
    printf 'ssh_host_key %s\nmachine_id %s\n' "${host_key}" "${machine_id}" > "${IDENTITY}"
    [ -n "${host_key}" ] && [ -n "${machine_id}" ]
}

# less_report: run less in an SSH terminal with the workaround (-d) unset.
# A warning makes less wait for RETURN, so it runs under a timeout. The
# hostname must appear, or the SSH command itself failed and proves nothing.
less_report() {
    local out name
    name=$(ssh_run hostname)
    login_ssh
    out=$(TERM=xterm-256color timeout 30 "${LOGIN_SSH[@]}" -tt "${LOGIN_USER}@127.0.0.1" \
        'env -u LESS -u SYSTEMD_LESS less -F /etc/hostname' < /dev/null 2>&1) || true
    if [ -z "${name}" ] || ! grep -qF "${name}" <<< "${out}"; then
        report "INFO less without LESS=-d: not run (issue #6)"
    elif grep -q "not fully functional" <<< "${out}"; then
        report "INFO less without LESS=-d: warns (keep the workaround, issue #6)"
    else
        report "INFO less without LESS=-d: no warning (the workaround can go, issue #6)"
    fi
}

collect_diagnostics() {
    sudo_run "journalctl -b --no-pager -u docker -u ${BRAND}-firstboot -u ${BRAND}-config" \
        > "${OUT}/journal.txt" 2>&1 || true
    { sudo_run "docker ps -a"; sudo_run "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT"; } \
        > "${OUT}/system.txt" 2>&1 || true
}
