#!/bin/bash
# tests/boot/boot-checks.sh
# Checks run from the host by boot-test.sh against the booted guest. Source
# this file; it uses boot-test.sh's settings (REPORT, OUT, SSH_PORT,
# LOGIN_USER, LOGIN_PASS, DEFAULT_PASS, KEY, BRAND, WAIT_SECS).
#
# QEMU's user networking forwards IPv4 only: use 127.0.0.1, never localhost
# (ssh-keyscan stops at localhost's IPv6 address).

report() { echo "$*" | tee -a "${REPORT}"; }

# The user a setup file creates
SETUP_USER="tester"

# make_setup_file <dest>: a kura-setup.json as Etchwise writes it (new user
# with LOGIN_PASS's hash and a new SSH key at KEY, password logins off,
# hostname, Wi-Fi, time zone)
make_setup_file() {
    ssh-keygen -q -t ed25519 -N "" -C "kura-boot-test" -f "${KEY}"
    jq -n --arg user "${SETUP_USER}" --arg hash "$(openssl passwd -6 "${LOGIN_PASS}")" \
          --arg key "$(cat "${KEY}.pub")" '{
        version: 1, hostname: "kura-ci",
        user: {name: $user, passwordHash: $hash},
        ssh: {enabled: true, passwordAuth: false, authorizedKeys: [$key]},
        wifi: {ssid: "CIWifi", psk: "password-ci", hidden: false, country: "FR"},
        timezone: "Europe/Paris", keyboard: "fr"}' > "$1"
}

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

# secure_boot_on: the firmware's SecureBoot variable (its 5th byte, after
# the attributes) is 1; the kernel's lockdown mode is reported with it
secure_boot_on() {
    local var=/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c value
    value=$(ssh_run "od -An -tu1 -j4 -N1 ${var}" 2>/dev/null | tr -d ' ')
    report "  SecureBoot variable: ${value:-missing}; lockdown: $(ssh_run "cat /sys/kernel/security/lockdown" 2>/dev/null)"
    [ "${value}" = "1" ]
}


# screendump <png>: the guest's screen, through the QEMU monitor socket
screendump() {
    python3 - "${MONITOR}" "$1" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.settimeout(10)
s.connect(sys.argv[1])
time.sleep(0.3)
s.recv(65536)
s.sendall(("screendump %s -f png\n" % sys.argv[2]).encode())
time.sleep(1)
s.close()
PY
}

# splash_screens <seconds>: a screenshot every 2 s while the system boots
# (splash-NN.png), run in the background: the Plymouth splash shows in some
splash_screens() {
    local n
    for n in $(seq -w 1 $(( $1 / 2 ))); do
        sleep 2
        screendump "${OUT}/splash-${n}.png" 2>/dev/null || true
    done
}

# The PC image's boot splash (ADR-018): the theme is the default and is in
# the initrd that boots
splash_theme_default() { [ "$(ssh_run /usr/sbin/plymouth-set-default-theme)" = kura ]; }
splash_in_initrd() {
    ssh_run 'lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -q "themes/kura/kura.script"'
}

# console_font: the first boot cached the Terminus 16x32 font setup
console_font() { ssh_run 'grep -q "Terminus32x16" /etc/console-setup/cached_setup_font.sh'; }

# setup_shown: kura-issue has put the setup outcome on the login screen
setup_shown() { ssh_run 'grep -q "setup applied" /etc/issue'; }

# login_screen: the console's login screen has the Kura look; saved as
# login.png
login_screen() {
    screendump "${OUT}/login.png" && [ -s "${OUT}/login.png" ] &&
        ssh_run 'grep -q "T H E   S T O R E H O U S E" /etc/issue'
}

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

# less_works: less in an SSH terminal shows a file without "terminal is not
# fully functional" (issue #6). A warning makes less wait for RETURN, so it
# runs under a timeout; the hostname must appear, or SSH itself failed.
less_works() {
    local out name
    name=$(ssh_run hostname)
    login_ssh
    out=$(TERM=xterm-256color timeout 30 "${LOGIN_SSH[@]}" -tt "${LOGIN_USER}@127.0.0.1" \
        'less -F /etc/hostname' < /dev/null 2>&1) || true
    [ -n "${name}" ] && grep -qF "${name}" <<< "${out}" && ! grep -q "not fully functional" <<< "${out}"
}

collect_diagnostics() {
    sudo_run "journalctl -b --no-pager -u docker -u ${BRAND}-firstboot -u ${BRAND}-config" \
        > "${OUT}/journal.txt" 2>&1 || true
    { sudo_run "docker ps -a"; sudo_run "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT"; } \
        > "${OUT}/system.txt" 2>&1 || true
}
