#!/usr/bin/env bats
# tests/shell/firstboot-setup.bats — tests for scripts/common/firstboot-setup.sh:
# first boot applies kura-setup.json, written to the boot partition by an
# imager (Etchwise), then deletes it. Device commands are stubbed; files are
# written under SETUP_ROOT.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
HASH='$y$j9T$abcdefghijklmnop$0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef'
KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKura0000000000000000000000000000000000000 chris@laptop'
PSK="$(printf 'a%.0s' {1..64})"

setup() {
    load test_helper
    SETUP_ROOT="${BATS_TEST_TMPDIR}/root"
    SETUP_BRAND=kura
    export SETUP_ROOT SETUP_BRAND
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/firstboot-setup.sh"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    BOOT="${BATS_TEST_TMPDIR}/boot"
    SSHD="${SETUP_ROOT}/etc/ssh/sshd_config.d/10-kura.conf"
    mkdir -p "${BOOT}" "${SETUP_ROOT}/etc/kura" "${SETUP_ROOT}/etc/ssh/sshd_config.d" \
             "${SETUP_ROOT}/usr/share/zoneinfo/Europe" "${SETUP_ROOT}/home/admin"
    touch "${SETUP_ROOT}/usr/share/zoneinfo/Europe/Paris"
    cp "${REPO_ROOT}/overlay/common/etc/kura/config.json" "${SETUP_ROOT}/etc/kura/config.json"
    printf 'PermitRootLogin prohibit-password\nPasswordAuthentication no\n\nMatch User admin\n    PasswordAuthentication yes\n' \
        > "${SSHD}"
    stub_device
}

# The image's login user and group are admin (uid/gid 1000); root, daemon and
# the docker group also exist. USER_NOW / GROUP_NOW track renames.
stub_device() {
    USER_NOW=admin GROUP_NOW=admin
    getent() {
        case "$1:$2" in
            passwd:1000) echo "${USER_NOW}:x:1000:1000::/home/${USER_NOW}:/bin/bash" ;;
            passwd:root) echo "root:x:0:0:root:/root:/bin/bash" ;;
            passwd:daemon) echo "daemon:x:1:1:daemon:/usr/sbin:/usr/sbin/nologin" ;;
            "passwd:${USER_NOW}") echo "${USER_NOW}:x:1000:1000::/home/${USER_NOW}:/bin/bash" ;;
            group:1000|"group:${GROUP_NOW}") echo "${GROUP_NOW}:x:1000:" ;;
            group:docker) echo "docker:x:995:" ;;
            *) return 2 ;;
        esac
    }
    usermod() { log_call "usermod $*"; USER_NOW="$2"; mkdir -p "${SETUP_ROOT}/home/$2"; }
    groupmod() { log_call "groupmod $*"; GROUP_NOW="$2"; }
    chpasswd() { log_call "chpasswd $* <<< $(cat)"; }
    chage() { log_call "chage $*"; }
    chown() { log_call "chown $*"; }
    systemctl() { log_call "systemctl $*"; }
}

full_setup() {
    cat > "${BOOT}/kura-setup.json" <<EOF
{"version":1,"hostname":"kura-01",
 "user":{"name":"chris","passwordHash":"${HASH}"},
 "ssh":{"enabled":true,"passwordAuth":false,"authorizedKeys":["${KEY}"]},
 "wifi":{"ssid":"Home Net","psk":"${PSK}","hidden":true,"country":"FR"},
 "timezone":"Europe/Paris","keyboard":"fr"}
EOF
}

conf() { jq -r "$1" "${SETUP_ROOT}/etc/kura/config.json"; }

# ---- apply_setup_dir: the whole file ----

@test "apply_setup_dir: nothing to do without a setup file" {
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

@test "apply_setup_dir: applies every setting and deletes the file" {
    full_setup
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ ! -e "${BOOT}/kura-setup.json" ]
    [ "$(conf .hostname)" = "kura-01" ]
    file_has "${CALLS}" "usermod -l chris -d /home/chris -m admin"
    file_has "${CALLS}" "chpasswd -e <<< chris:${HASH}"
    [ "$(conf '.networkConfig.wifi.networks[0].ssid')" = "Home Net" ]
    [ "$(readlink "${SETUP_ROOT}/etc/localtime")" = "/usr/share/zoneinfo/Europe/Paris" ]
    file_has "${SETUP_ROOT}/etc/default/keyboard" 'XKBLAYOUT="fr"'
}

@test "apply_setup_dir: secrets never reach a command line (the audit log records them)" {
    full_setup
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    run grep -F -e "usermod -p" -e "${PSK}" "${CALLS}"
    [ "$status" -ne 0 ]
}

@test "apply_setup_dir: keys left out keep the image's defaults" {
    echo '{"version":1,"hostname":"lab"}' > "${BOOT}/kura-setup.json"
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ "$(conf .hostname)" = "lab" ]
    [ "$(conf .networkConfig.wifi.enable)" = "false" ]
    [ ! -e "${CALLS}" ]
    [ ! -e "${SETUP_ROOT}/etc/localtime" ]
}

@test "apply_setup_dir: an invalid file is ignored and deleted (it may hold secrets)" {
    echo '{"version":1,"hostname":"bad name;reboot"}' > "${BOOT}/kura-setup.json"
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    output_has "hostname"
    [ ! -e "${BOOT}/kura-setup.json" ]
    [ "$(conf .hostname)" = "kura" ]
}

@test "apply_setup_dir: records that the setup was applied (the login screen shows it)" {
    full_setup
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/setup-status")" = "applied" ]
}

@test "apply_setup_dir: records why an invalid file was ignored" {
    echo '{"version":1,"user":{"name":"root","passwordHash":"'"${HASH}"'"}}' > "${BOOT}/kura-setup.json"
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    [ "$(cat "${SETUP_ROOT}/var/lib/kura/setup-status")" = \
      "ignored: invalid user name (taken by a system account or group)" ]
}

@test "apply_setup_dir: a step that fails without a reason points at the journal" {
    full_setup
    usermod() { return 1; }
    run apply_setup_dir "${BOOT}"
    [ "$status" -ne 0 ]
    file_has "${SETUP_ROOT}/var/lib/kura/setup-status" "incomplete, retrying: a step failed (journalctl -u kura-firstboot)"
}

@test "apply_setup_dir: bad Wi-Fi settings skip the Wi-Fi only" {
    echo '{"version":1,"hostname":"lab","wifi":{"ssid":"Bob'"'"'s phone","psk":"password1"}}' \
        > "${BOOT}/kura-setup.json"
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    output_has "Wi-Fi"
    [ "$(conf .hostname)" = "lab" ]
    [ "$(conf .networkConfig.wifi.enable)" = "false" ]
}

@test "apply_setup_dir: a failed step keeps the file so first boot retries" {
    full_setup
    # shellcheck disable=SC2329  # invoked by apply_setup_dir
    usermod() { return 1; }
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 1 ]
    [ -e "${BOOT}/kura-setup.json" ]
}

@test "apply_setup_dir: the file is overwritten before it is deleted" {
    full_setup
    wipe_file() { log_call "wipe $1"; }
    run apply_setup_dir "${BOOT}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "wipe ${BOOT}/kura-setup.json"
}

# with_failing_rm <command...>: rm fails inside the subshell run makes only
# (overriding it in the test itself would also break bats's own cleanup)
with_failing_rm() {
    # shellcheck disable=SC2329  # invoked by the command
    rm() { return 1; }
    "$@"
}

@test "apply_setup_dir: a file that cannot be deleted is an error" {
    full_setup
    run with_failing_rm apply_setup_dir "${BOOT}"
    [ "$status" -eq 1 ]
    output_has "delete"
}

# ---- validate_setup ----

reject() {  # reject <json> <word expected in the message>
    echo "$1" > "${BOOT}/s.json"
    run validate_setup "${BOOT}/s.json"
    [ "$status" -ne 0 ]
    output_has "$2"
}

@test "validate_setup: accepts the full example" {
    full_setup
    run validate_setup "${BOOT}/kura-setup.json"
    [ "$status" -eq 0 ]
}

@test "validate_setup: rejects broken JSON, unknown versions and huge files" {
    reject '{"version":1,' "JSON"
    reject '{"version":2}' "version"
    reject '{"version":"1"}' "version"
    head -c 70000 /dev/zero | tr '\0' ' ' > "${BOOT}/big.json"
    run validate_setup "${BOOT}/big.json"
    [ "$status" -ne 0 ]
    output_has "too large"
}

@test "validate_setup: rejects unsafe or taken user and group names" {
    reject '{"version":1,"user":{"name":"Chris"}}' "user name"
    reject '{"version":1,"user":{"name":"x;rm"}}' "user name"
    reject '{"version":1,"user":{"name":"root"}}' "user name"
    reject '{"version":1,"user":{"name":"daemon"}}' "user name"
    reject '{"version":1,"user":{"name":"docker"}}' "user name"
}

@test "validate_setup: accepts keeping the image's own user name" {
    echo '{"version":1,"user":{"name":"admin"}}' > "${BOOT}/s.json"
    run validate_setup "${BOOT}/s.json"
    [ "$status" -eq 0 ]
}

@test "validate_setup: the password must be a crypt hash, never plain text" {
    reject '{"version":1,"user":{"name":"chris","passwordHash":"hunter2"}}' "password"
    reject '{"version":1,"user":{"name":"chris","passwordHash":"$6$a:b"}}' "password"
}

@test "validate_setup: rejects bad SSH settings" {
    reject '{"version":1,"ssh":{"enabled":"yes"}}' "ssh"
    reject '{"version":1,"ssh":{"authorizedKeys":["not a key"]}}' "SSH key"
    reject '{"version":1,"ssh":{"authorizedKeys":[""]}}' "SSH key"
    reject "$(jq -nc '{version:1,ssh:{authorizedKeys:["ssh-ed25519 AAAA x\nssh-rsa BBBB"]}}')" "SSH key"
}

@test "validate_setup: refuses SSH with password logins off and no key (no way in)" {
    reject '{"version":1,"ssh":{"passwordAuth":false}}' "no way to log in"
    reject '{"version":1,"ssh":{"enabled":true,"passwordAuth":false,"authorizedKeys":[]}}' "no way to log in"
}

@test "validate_setup: rejects bad time zones and keyboard layouts" {
    reject '{"version":1,"timezone":"../../etc/shadow"}' "time zone"
    reject '{"version":1,"keyboard":"fr\"; reboot"}' "keyboard"
}

@test "validate_wifi: rejects bad Wi-Fi settings" {
    rejected() {  # rejected <json> <word>
        echo "$1" > "${BOOT}/w.json"
        run validate_wifi "${BOOT}/w.json"
        [ "$status" -ne 0 ]
        output_has "$2"
    }
    rejected '{"wifi":{"ssid":";evil","psk":"password1"}}' "SSID"
    rejected '{"wifi":{"ssid":"Home"}}' "Wi-Fi password"
    rejected '{"wifi":{"ssid":"Home","psk":"short"}}' "Wi-Fi password"
    rejected "$(jq -nc '{wifi:{ssid:"Home",psk:"pass\nword1"}}')" "Wi-Fi password"
    rejected '{"wifi":{"ssid":"Home","psk":"password1","country":"france"}}' "country"
    rejected '{"wifi":{"ssid":"Home","psk":"password1","hidden":"yes"}}' "wifi"
}

# ---- single steps ----

@test "setup_user: renames user and group, sets the hash and lifts the forced change" {
    run setup_user chris "${HASH}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "groupmod -n chris admin"
    file_has "${CALLS}" "chage -d -1 chris"
    file_has "${SSHD}" "Match User chris"
}

@test "setup_user: a retry after a half-done rename finishes it" {
    USER_NOW=chris   # usermod -l worked, groupmod and the sshd rule did not
    run setup_user chris "${HASH}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "groupmod -n chris admin"
    file_has "${SSHD}" "Match User chris"
    run grep -q "usermod" "${CALLS}"
    [ "$status" -ne 0 ]
}

@test "setup_user: keeping the name only sets the password" {
    run setup_user admin "${HASH}"
    [ "$status" -eq 0 ]
    run grep -q "usermod\|groupmod" "${CALLS}"
    [ "$status" -ne 0 ]
    file_has "${CALLS}" "chpasswd -e <<< admin:${HASH}"
}

@test "setup_ssh: installs the keys for the login user, private to them" {
    run setup_ssh true true "${KEY}"
    [ "$status" -eq 0 ]
    file_has "${SETUP_ROOT}/home/admin/.ssh/authorized_keys" "${KEY}"
    file_has "${CALLS}" "chown -R admin: ${SETUP_ROOT}/home/admin/.ssh"
}

@test "setup_ssh: password logins off drops only the login user's exception" {
    run setup_ssh true false "${KEY}"
    [ "$status" -eq 0 ]
    run grep -q "Match\|PasswordAuthentication yes" "${SSHD}"
    [ "$status" -ne 0 ]
    file_has "${SSHD}" "PermitRootLogin prohibit-password"
    file_has "${SSHD}" "PasswordAuthentication no"
}

@test "setup_ssh: SSH off disables the server" {
    run setup_ssh false true
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "systemctl --no-block disable --now ssh.service ssh.socket"
}

@test "setup_hostname: hands the name to os-config" {
    run setup_hostname kura-01
    [ "$status" -eq 0 ]
    [ "$(conf .hostname)" = "kura-01" ]
}

@test "setup_wifi_config: hands the network to os-config and sets the country" {
    run setup_wifi_config "Home Net" "password1" true FR
    [ "$status" -eq 0 ]
    [ "$(conf .networkConfig.wifi.enable)" = "true" ]
    [ "$(conf '.networkConfig.wifi.networks[0] | [.ssid, .psk, .hidden] | join(",")')" = "Home Net,password1,true" ]
    [ "$(conf .networkConfig.wifi.defaultInterface)" = "wlan0" ]
    file_has "${SETUP_ROOT}/etc/modprobe.d/cfg80211.conf" "options cfg80211 ieee80211_regdom=FR"
}

@test "edit_config: config.json stays private to root (it holds the Wi-Fi key)" {
    run setup_wifi_config "Home" "password1" false ""
    [ "$status" -eq 0 ]
    [ "$(file_mode "${SETUP_ROOT}/etc/kura/config.json")" = "600" ]
}

@test "setup_timezone: an unknown zone is skipped, not fatal" {
    run setup_timezone Mars/Olympus
    [ "$status" -eq 0 ]
    output_has "Mars/Olympus"
    [ ! -e "${SETUP_ROOT}/etc/localtime" ]
}

# ---- boot partition ----

@test "boot_partition: partition 1 of the root disk (Pi SD card and x86 disks)" {
    stub_disk_tools /dev/mmcblk0p2 mmcblk0
    run boot_partition
    [ "$output" = "/dev/mmcblk0p1" ]
    stub_disk_tools /dev/sda2 sda
    run boot_partition
    [ "$output" = "/dev/sda1" ]
    stub_disk_tools /dev/nvme0n1p2 nvme0n1
    run boot_partition
    [ "$output" = "/dev/nvme0n1p1" ]
}

@test "boot_partition: none on a live system" {
    stub_disk_tools overlay ""
    run boot_partition
    [ "$status" -ne 0 ]
}

stub_boot_fat() {  # a FAT boot partition holding BOOT's files
    boot_partition() { echo /dev/mmcblk0p1; }
    is_fat_partition() { return 0; }
    mount() { log_call "mount $*"; MOUNTED="${!#}"; cp -R "${BOOT}/." "${MOUNTED}/"; }
    umount() { log_call "umount $*"; }
}

@test "apply_setup: mounts the FAT boot partition without exec, suid or devices" {
    stub_boot_fat
    run apply_setup
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "mount -t vfat -o nosuid,nodev,noexec,umask=077 /dev/mmcblk0p1"
    file_has "${CALLS}" "umount"
}

@test "apply_setup: a FAT boot partition that will not mount is an error" {
    stub_boot_fat
    # shellcheck disable=SC2329  # invoked by apply_setup
    mount() { return 32; }
    run apply_setup
    [ "$status" -eq 1 ]
    output_has "mount"
}

@test "apply_setup: no FAT boot partition, nothing to do" {
    stub_boot_fat
    is_fat_partition() { return 1; }
    run apply_setup
    [ "$status" -eq 0 ]
    [ ! -e "${CALLS}" ]
}

# ---- image wiring ----

@test "the image ships what the setup needs: jq, time zones, console keymaps" {
    local list="${REPO_ROOT}/config/packages-common.list"
    for pkg in jq tzdata console-setup; do
        grep -qx "${pkg}" "${list}"
    done
}

@test "the setup accepts exactly the SSIDs os-config writes" {
    local os_config="${REPO_ROOT}/packages/os-config/src/os-config"
    file_has "${os_config}" "SAFE_SSID_RE='${SSID_RE}'"
}

@test "disk_partition: nvme and mmc disks take a p before the number" {
    [ "$(disk_partition nvme0n1 1)" = "nvme0n1p1" ]
    [ "$(disk_partition mmcblk0 1)" = "mmcblk0p1" ]
    [ "$(disk_partition sda 1)" = "sda1" ]
}
