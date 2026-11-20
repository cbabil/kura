#!/bin/bash
# tests/boot/boot-checks.sh
# Checks run from the host by boot-test.sh against the booted guest. Source
# this file; it uses boot-test.sh's settings (REPORT, OUT, SSH_PORT,
# LOGIN_USER, LOGIN_PASS, ONE_TIME_PASS, KEY, BRAND, WAIT_SECS).
#
# QEMU's user networking forwards IPv4 only: use 127.0.0.1, never localhost
# (ssh-keyscan stops at localhost's IPv6 address).

report() { echo "$*" | tee -a "${REPORT}"; }

# report_facts <text>: what a check read from the guest, indented in the report
# shellcheck disable=SC2001  # indent every line, not one substitution
report_facts() { sed 's/^/  /' <<< "$1" >> "${REPORT}"; }

# The user a setup file creates
SETUP_USER="tester"

# The disk layout the setup file asks for (LAYOUT, from boot-test.sh):
# server: a 4 GiB root, /tmp capped at 1 GiB, 1 GiB volumes for /var/log and
#   /var/tmp, Docker on the rest
# full: every folder kind on its own volume, nested under /var, /tmp on disk,
#   a folder of the user's own and swap, Docker on the rest
LAYOUT_SERVER='{rootGiB: 4, tmpGiB: 1, volumes: [{mount: "/var/log", sizeGiB: 1},
    {mount: "/var/tmp", sizeGiB: 1}, {mount: "/var/lib/docker"}]}'
LAYOUT_FULL='{rootGiB: 4, swapGiB: 1, volumes: [{mount: "/var/lib/docker"},
    {mount: "/var/lib", sizeGiB: 2}, {mount: "/var", sizeGiB: 2}, {mount: "/var/log", sizeGiB: 1},
    {mount: "/tmp", sizeGiB: 1}, {mount: "/echange", sizeGiB: 1}]}'

# make_setup_file <dest>: a kura-setup.json as Etchwise writes it (new user
# with LOGIN_PASS's hash and a new SSH key at KEY, password logins off,
# hostname, Wi-Fi, time zone, LAYOUT's disk layout, and Kura Desktop on or
# off as DESKTOP says)
LAYOUT="${LAYOUT:-server}"   # installer-test.sh sources this file without them
DESKTOP="${DESKTOP:-true}"

make_setup_file() {
    local layout="${LAYOUT_SERVER}"
    [ "${LAYOUT}" != full ] || layout="${LAYOUT_FULL}"
    ssh-keygen -q -t ed25519 -N "" -C "kura-boot-test" -f "${KEY}"
    jq -n --arg user "${SETUP_USER}" --arg hash "$(openssl passwd -6 "${LOGIN_PASS}")" \
          --arg key "$(cat "${KEY}.pub")" --argjson desktop "${DESKTOP}" '{
        version: 1, hostname: "kura-ci",
        user: {name: $user, passwordHash: $hash},
        ssh: {enabled: true, passwordAuth: false, authorizedKeys: [$key]},
        wifi: {ssid: "CIWifi", psk: "password-ci", hidden: false, country: "FR"},
        timezone: "Europe/Paris", keyboard: "fr", desktop: $desktop,
        storage: '"${layout}"'}' > "$1"
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

# console_password: the one-time password (firstboot-password.sh) as the owner
# reads it on the login screen, which the serial console shows too
console_password() {
    local pw
    pw=$(LC_ALL=C grep -aoE '[a-km-np-z2-9]{4}-[a-km-np-z2-9]{4}-[a-km-np-z2-9]{4} · one-time' "${SERIAL}" | tail -1)
    [ -n "${pw}" ] && ONE_TIME_PASS="${pw%% *}"
}

# The image's public default password (admin) never logs in over SSH
default_password_refused() {
    ! sshpass -p "${PUBLIC_DEFAULT_PASS}" ssh "${SSH_OPTS[@]}" -o PubkeyAuthentication=no \
        "${LOGIN_USER}@127.0.0.1" true 2>/dev/null
}

# The one-time password must only reach a forced password change (first-login.exp
# fails if it gets a shell); from then on LOGIN_PASS is the password.
first_login_changes_password() {
    "$(dirname "$0")/first-login.exp" "${SSH_PORT}" "${LOGIN_USER}" "${ONE_TIME_PASS}" "${LOGIN_PASS}" \
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


# screendump <file> [format]: the guest's screen (png, or ppm for checking
# colours), through the QEMU monitor socket
screendump() {
    python3 - "${MONITOR}" "$1" "${2:-png}" <<'PY'
import socket, sys, time
s = socket.socket(socket.AF_UNIX)
s.settimeout(10)
s.connect(sys.argv[1])
time.sleep(0.3)
s.recv(65536)
s.sendall(("screendump %s -f %s\n" % (sys.argv[2], sys.argv[3])).encode())
time.sleep(1)
s.close()
PY
}

# splash_screens <seconds>: first, for 20 s, a screen as fast as the
# monitor gives them (about 1.3 s each: GRUB's menu is up for 3 s), as
# grub-NN.png for grub_themed; then a screenshot every 2 s while the system
# boots (splash-NN.png), where the Plymouth splash shows. Run in the
# background.
splash_screens() {
    local n
    for n in $(seq -w 1 15); do
        screendump "${OUT}/grub-${n}.png" 2>/dev/null || true
    done
    for n in $(seq -w 1 $(( $1 / 2 ))); do
        sleep 2
        screendump "${OUT}/splash-${n}.png" 2>/dev/null || true
    done
}

# screens_show <file-glob> <background> <rrggbb>...: one of the screenshots
# is mostly the background colour and has all the others (sampled every 7th
# pixel: not a multiple of 4, where a 24/32-bit mix-up still looks right).
# Reads QEMU's PNGs (8-bit RGB or RGBA) with zlib only.
screens_show() {
    python3 - "$@" <<'PY'
import collections, glob, struct, sys, zlib

def pixels(path):
    data = open(path, "rb").read()
    pos, idat, width, height, kind = 8, b"", 0, 0, 2
    while pos < len(data):
        size, tag = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + size]
        if tag == b"IHDR":
            width, height, _, kind = struct.unpack(">IIBB", body[:10])
        elif tag == b"IDAT":
            idat += body
        pos += size + 12
    bpp = 4 if kind == 6 else 3
    raw, stride, prev, colours = zlib.decompress(idat), width * bpp, bytearray(width * bpp), collections.Counter()
    for y in range(height):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = line[i - bpp] if i >= bpp else 0
            b, c = prev[i], prev[i - bpp] if i >= bpp else 0
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + b) & 255
            elif f == 3: line[i] = (line[i] + (a + b) // 2) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        colours.update(bytes(line[i:i + 3]) for i in range(0, stride, bpp * 7))
        prev = line
    return colours

wanted = [bytes.fromhex(c) for c in sys.argv[2:]]
for name in sorted(glob.glob(sys.argv[1])):
    seen = pixels(name)
    if seen[wanted[0]] * 2 > sum(seen.values()) and all(c in seen for c in wanted):
        print("  found in " + name.rsplit("/", 1)[-1])
        sys.exit(0)
sys.exit(1)
PY
}

# kura_package: dpkg knows the image's Kura version (ADR-025), so apt can
# install the next one
kura_package() {
    local facts
    facts=$(ssh_run "dpkg-query -W -f='\${Status} \${Version}' ${BRAND}; echo; cat /usr/lib/${BRAND}/release")
    report_facts "${facts}"
    [[ "${facts}" == "install ok installed "* ]] && [[ "${facts}" == *BRAND_VERSION=* ]]
}

# installer_full_size: the installer's last screens are at the display's
# resolution (1920 wide here): the boot menu's smaller mode was left
installer_full_size() {
    python3 - "${OUT}" <<'PY'
import glob, struct, sys
last = sorted(glob.glob(sys.argv[1] + "/installer-*.png"))[-1]
width = struct.unpack(">I", open(last, "rb").read()[16:20])[0]
print("  %s is %d wide" % (last.rsplit("/", 1)[-1], width))
sys.exit(0 if width == 1920 else 1)
PY
}

# grub_themed: GRUB's menu in Kura's look (ADR-021) on one of the first
# screens: the navy background and the light purple selected entry
grub_themed() { screens_show "${OUT}/grub-*.png" 0f172a a970ff; }

# installer_drawn: the installer's own screen, readable: its navy
# background, the logo's two purples and the green of a finished step (a
# wrong screen format from the boot loader shows none of them)
installer_drawn() { screens_show "${OUT}/installer-*.png" 0f172a a970ff 9146ff 23ce6b; }

# The PC image's boot splash (ADR-018): the theme is the default and is in
# the initrd that boots
splash_theme_default() { [ "$(ssh_run /usr/sbin/plymouth-set-default-theme)" = kura ]; }
splash_in_initrd() {
    ssh_run 'lsinitramfs "/boot/initrd.img-$(uname -r)" | grep -q "themes/kura/kura.script"'
}

# console_font: the first boot cached the Terminus 16x32 font setup
console_font() { ssh_run 'grep -q "Terminus32x16" /etc/console-setup/cached_setup_font.sh'; }

# layout_built: the setup file's disk layout (LAYOUT's)
layout_built() {
    if [ "${LAYOUT}" = full ]; then full_layout_built; else server_layout_built; fi
}

# server_layout_built: the root sized, the volumes mounted with their
# options, /var/tmp still world-writable, /tmp capped
server_layout_built() {
    local facts status root docker logopts mode tmpopts
    facts=$(ssh_run "cat /var/lib/${BRAND}/storage-status
        lsblk -bdno SIZE \$(findmnt -no SOURCE /)
        findmnt -no SOURCE /var/lib/docker
        findmnt -no OPTIONS /var/log
        stat -c %a /var/tmp
        findmnt -no OPTIONS /tmp")
    report_facts "${facts}"
    { read -r status; read -r root; read -r docker; read -r logopts; read -r mode; read -r tmpopts; } <<< "${facts}"
    [ "${status}" = "applied" ] && [ "${root}" = "4294967296" ] &&
    [ "${docker}" = "/dev/mapper/${BRAND}-var--lib--docker" ] &&
    [[ "${logopts}" == *noexec* ]] && [ "${mode}" = "1777" ] &&
    [[ "${tmpopts}" =~ size=(1048576k|1G) ]]
}

# full_layout_built: each folder on its volume (the nested ones inside their
# parents, /tmp world-writable on disk, not the RAM disk), swap on, dpkg's
# database readable from the moved /var/lib, and the root's old copies gone
full_layout_built() {
    local facts
    facts=$(ssh_run "cat /var/lib/${BRAND}/storage-status
        for d in /var /var/lib /var/lib/docker /var/log /tmp /echange; do findmnt -no SOURCE \"\$d\"; done
        stat -c %a /tmp
        [ \"\$(awk 'NR > 1 { print \$1 }' /proc/swaps | xargs -r readlink -f)\" = \"\$(readlink -f /dev/${BRAND}/swap)\" ] && echo swap-on
        dpkg-query -W -f='\${Status}\n' bash")
    facts+=$'\n'$(sudo_run "sh -c 'v=\$(mktemp -d) && mount --bind / \$v && find \$v/var -mindepth 1 | wc -l; umount \$v; rmdir \$v'")
    report_facts "${facts}"
    [ "${facts}" = "applied
/dev/mapper/${BRAND}-var
/dev/mapper/${BRAND}-var--lib
/dev/mapper/${BRAND}-var--lib--docker
/dev/mapper/${BRAND}-var--log
/dev/mapper/${BRAND}-tmp
/dev/mapper/${BRAND}-echange
1777
swap-on
install ok installed
0" ]
}

# layout_after_restart: the layout comes back on the next boot (fstab, LVM
# activation, and the root's PARTUUID unchanged by the resize)
layout_after_restart() { restart_device && layout_built; }

# restart_device: restart, and wait until SSH answers again
restart_device() {
    sudo_run "systemctl reboot" || true
    sleep 20
    wait_for "SSH after the restart" ssh_run true
}

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
    local states units=("$@")
    [ "$#" -gt 0 ] || units=(docker "${BRAND}-firstboot" "${BRAND}-ssh-keygen" "${BRAND}-config")
    states=$(ssh_run systemctl is-active "${units[@]}" || true)
    report_facts "${states}"
    [ "$(echo "${states}" | grep -cx active)" -eq "${#units[@]}" ]
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
    # every boot (the disk layout is built in one and finished in the next),
    # with the units a failed check most often comes down to
    sudo_run "journalctl --no-pager -u docker -u ${BRAND}-firstboot -u ${BRAND}-config \
        -u ${BRAND}-storage -u ${BRAND}-storage-finish \
        -u ${BRAND}-desktopd -u ${BRAND}-desktop-cert -u ${BRAND}-helper" \
        > "${OUT}/journal.txt" 2>&1 || true
    sudo_run "systemctl --no-pager --failed; systemctl --no-pager status ${BRAND}-desktopd ${BRAND}-helper
        namei -l /var/lib/${BRAND}/desktop/tls.crt; id ${BRAND}-desktop
        journalctl --no-pager -u systemd-sysusers -u systemd-tmpfiles-setup | tail -20" \
        > "${OUT}/units.txt" 2>&1 || true
    { sudo_run "docker ps -a"; sudo_run "lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT"; } \
        > "${OUT}/system.txt" 2>&1 || true
}
