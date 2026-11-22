#!/usr/bin/env bats
# tests/shell/desktop-settings.bats — packages/os-desktop/src/os-settings, the
# root command behind Kura Desktop's Settings (ADR-029).

setup() {
    load test_helper
    ROOT="${BATS_TEST_TMPDIR}/root"
    CALLS="${BATS_TEST_TMPDIR}/calls"
    mkdir -p "${ROOT}/etc/kura" "${ROOT}/etc/NetworkManager/system-connections" \
        "${ROOT}/usr/share/zoneinfo/Europe" "${ROOT}/var/lib/kura/desktop" "${ROOT}/run"
    touch "${ROOT}/usr/share/zoneinfo/Europe/Paris" "${ROOT}/usr/share/zoneinfo/UTC" "${CALLS}"
    cat > "${ROOT}/etc/kura/config.json" <<'JSON'
{"hostname": "kura", "networkConfig": {"wifi": {"enable": false}, "ethernet": {"enable": true}}}
JSON
    printf 'root:x:0:0::/root:/bin/sh\nanna:x:1000:1000::/home/anna:/bin/bash\nbob:x:1001:1001::/home/bob:/bin/bash\ndaemon:x:1:1::/:/usr/sbin/nologin\n' > "${ROOT}/etc/passwd"
    printf 'sudo:x:27:anna\n' > "${ROOT}/etc/group"
    local tmp="${BATS_TEST_TMPDIR}/settings.sh"
    sed -e 's|__BRAND__|kura|g' -e '/^set -euo pipefail$/d' -e '/^main "\$@"$/d' \
        "${BATS_TEST_DIRNAME}/../../packages/os-desktop/src/os-settings" > "${tmp}"
    branded settings-screens > /dev/null
    # shellcheck disable=SC1090
    SETTINGS_ROOT="${ROOT}" SETTINGS_LIB="${BATS_TEST_TMPDIR}" source "${tmp}"
    mkdir -p "${ROOT}/home"
    hostname() { [ $# -gt 0 ] || jq -r .hostname "${ROOT}/etc/kura/config.json"; }
    pgrep() { return 1; }
    sleep() { :; }
    for tool in systemctl systemd-run timedatectl nmcli useradd userdel chpasswd gpasswd pkill chown; do
        eval "${tool}() { [ \"${tool}\" != chpasswd ] || cat >> \"\${CALLS}.stdin\"; log_call ${tool} \"\$@\"; }"
    done
    SECRET="${BATS_TEST_TMPDIR}/secret"
}

config() { jq -c "$1" "${ROOT}/etc/kura/config.json"; }
secret() { printf '%s' "$1" > "${SECRET}"; }

# ---- hostname ----

@test "hostname: the certificate is remade only once the new name is in place" {
    hostname() { [ $# -gt 0 ] || echo kura; }   # kura-config never applies it
    run main hostname attic-nas
    [ "$status" -ne 0 ]
    ! grep -q desktop-cert "${CALLS}"
}

@test "hostname: goes to config.json, is applied now, and the certificate is remade" {
    touch "${ROOT}/var/lib/kura/desktop/tls.crt" "${ROOT}/var/lib/kura/desktop/tls.key" "${ROOT}/var/lib/kura/desktop/fingerprint"
    run main hostname attic-nas
    [ "$status" -eq 0 ]
    [ "$(config .hostname)" = '"attic-nas"' ]
    [ ! -e "${ROOT}/var/lib/kura/desktop/tls.crt" ] && [ ! -e "${ROOT}/var/lib/kura/desktop/fingerprint" ]
    file_has "${CALLS}" "systemctl restart kura-config.service"
    file_has "${CALLS}" "kura-desktop-cert.service"
}

@test "hostname: only a plain name is accepted" {
    for bad in "" "-x" "x-" "Attic" "a b" "a.b" 'a;reboot' "$(printf 'a%.0s' {1..64})"; do
        run main hostname "${bad}"
        [ "$status" -ne 0 ]
    done
    [ "$(config .hostname)" = '"kura"' ]
    [ ! -s "${CALLS}" ]
}

# ---- time ----

@test "timezone: a zone the system has is set; anything else is refused" {
    run main timezone Europe/Paris
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "timedatectl set-timezone Europe/Paris"
    for bad in "Mars/Olympus" "../../etc/passwd" "Europe/../UTC" "" "Europe/Paris; reboot" "--secret-file" "-UTC"; do
        run main timezone "${bad}"
        [ "$status" -ne 0 ]
    done
    [ "$(grep -c set-timezone "${CALLS}")" -eq 1 ]
}

@test "ntp: on or off, nothing else" {
    run main ntp off
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "timedatectl set-ntp false"
    run main ntp on
    file_has "${CALLS}" "timedatectl set-ntp true"
    run main ntp maybe
    [ "$status" -ne 0 ]
}

@test "screen: turned on and off where the image has it, refused where it has not" {
    run main screen on
    [ "$status" -ne 0 ]
    [[ "$output" == *"no local screen"* ]]
    mkdir -p "${ROOT}/usr/lib/systemd/system"
    touch "${ROOT}/usr/lib/systemd/system/kura-kiosk.service"
    # every PC image has the unit; only one built for it has the browser
    run main screen on
    [ "$status" -ne 0 ]
    mkdir -p "${ROOT}/usr/bin"
    printf '#!/bin/sh\n' > "${ROOT}/usr/bin/cage"
    chmod +x "${ROOT}/usr/bin/cage"
    run main screen on
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "systemctl enable --now kura-kiosk.service"
    run main screen off
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "systemctl disable --now kura-kiosk.service"
    run main screen dim
    [ "$status" -ne 0 ]
}

# ---- Remote Desktop (ADR-035) ----

# rdp_image: a server whose image has Remote Desktop, firewall library included
rdp_image() {
    mkdir -p "${ROOT}/usr/sbin" "${ROOT}/usr/lib/kura/security" "${ROOT}/etc/kura/security"
    printf '#!/bin/sh\n' > "${ROOT}/usr/sbin/xrdp"
    printf '#!/bin/sh\n' > "${ROOT}/usr/lib/kura/kura-rdp-session"
    chmod +x "${ROOT}/usr/sbin/xrdp" "${ROOT}/usr/lib/kura/kura-rdp-session"
    sed 's|__BRAND__|kura|g' "${BATS_TEST_DIRNAME}/../../packages/os-security/src/lib/firewall.sh" \
        > "${ROOT}/usr/lib/kura/security/firewall.sh"
    echo '{"network_security": {"firewall_preset": "strict", "mdns": true}}' > "${ROOT}/etc/kura/security/hardening.json"
    chmod 0600 "${ROOT}/etc/kura/security/hardening.json"
    fake_iptables
    for tool in update-alternatives make-ssl-cert xrdp-keygen chgrp chmod pkill; do
        eval "${tool}() { log_call ${tool} \"\$@\"; }"
    done
}

rdp_flag() { jq -r '.network_security.rdp' "${ROOT}/etc/kura/security/hardening.json"; }

@test "rdp: refused where the image has none" {
    run main rdp on
    [ "$status" -ne 0 ]
    output_has "no Remote Desktop"
    # every PC image has what a session shows; only one built for it has xrdp
    mkdir -p "${ROOT}/usr/lib/kura"
    printf '#!/bin/sh\n' > "${ROOT}/usr/lib/kura/kura-rdp-session"
    chmod +x "${ROOT}/usr/lib/kura/kura-rdp-session"
    run main rdp on
    [ "$status" -ne 0 ]
    [ ! -s "${CALLS}" ]
}

@test "rdp on: the port opens, the firewall remembers it, and the session starts" {
    rdp_image
    run main rdp on
    [ "$status" -eq 0 ]
    grep -qxF -- "INPUT -p tcp --dport 3389 -s 192.168.0.0/16 -j ACCEPT" "${RULES}"
    file_has "${CALLS}" "systemctl enable --now xrdp-sesman.service xrdp.service"
    file_has "${CALLS}" "update-alternatives --install /usr/bin/x-session-manager x-session-manager /usr/lib/kura/kura-rdp-session 90"
    [ "$(rdp_flag)" = "true" ]
    # the rest of the security settings is as it was, and still root's alone
    [ "$(jq -r '.network_security.mdns' "${ROOT}/etc/kura/security/hardening.json")" = "true" ]
    [ "$(file_mode "${ROOT}/etc/kura/security/hardening.json")" = "600" ]
    [ "$(grep -c . "${RULES}")" -eq 8 ]
    # the rules are in before anything listens, not after
    [ "$(grep -n -- "-j ACCEPT" "${RULES}.calls" | wc -l)" -ge 4 ]
    # this device's own keys, made here: the image has none (they would be every device's)
    file_has "${CALLS}" "make-ssl-cert generate-default-snakeoil"
    file_has "${CALLS}" "xrdp-keygen xrdp ${ROOT}/etc/xrdp/rsakeys.ini"
    file_has "${CALLS}" "chgrp xrdp ${ROOT}/etc/xrdp/rsakeys.ini"
}

@test "rdp off: the session stops, the port closes, and stays closed after a restart" {
    rdp_image
    main rdp on
    : > "${CALLS}"
    run main rdp off
    [ "$status" -eq 0 ]
    # the session manager goes too, and the sessions with it
    file_has "${CALLS}" "systemctl disable --now xrdp-sesman.service xrdp.service"
    file_has "${CALLS}" "update-alternatives --remove x-session-manager /usr/lib/kura/kura-rdp-session"
    # sessions that outlive the session manager end with their X server
    file_has "${CALLS}" "pkill -f xrdp/xorg.conf"
    [ ! -s "${RULES}" ]
    [ "$(rdp_flag)" = "false" ]
    run main rdp maybe
    [ "$status" -ne 0 ]
}

@test "rdp on: a firewall that refuses leaves everything off" {
    rdp_image
    iptables() { return 1; }
    run main rdp on
    [ "$status" -ne 0 ]
    output_has "firewall did not open"
    [ "$(rdp_flag)" = "false" ]
    run grep "systemctl enable" "${CALLS}"
    [ "$status" -ne 0 ]
}

@test "rdp on: a session that does not start closes the port again" {
    rdp_image
    systemctl() { log_call systemctl "$@"; [ "$1" != "enable" ]; }
    run main rdp on
    [ "$status" -ne 0 ]
    output_has "did not start"
    [ "$(rdp_flag)" = "false" ]
    file_has "${CALLS}" "systemctl disable --now xrdp-sesman.service xrdp.service"
    # the port is closed again
    [ ! -s "${RULES}" ]
}

@test "rdp on: keys the device already has are kept" {
    rdp_image
    mkdir -p "${ROOT}/etc/ssl/private" "${ROOT}/etc/xrdp"
    echo k > "${ROOT}/etc/ssl/private/ssl-cert-snakeoil.key"
    echo k > "${ROOT}/etc/xrdp/rsakeys.ini"
    run main rdp on
    [ "$status" -eq 0 ]
    run grep -E "make-ssl-cert|xrdp-keygen" "${CALLS}"
    [ "$status" -ne 0 ]
}

@test "rdp off: a port that cannot be closed is said, and the firewall still told to keep it closed" {
    rdp_image
    main rdp on
    eval "real_$(declare -f iptables)"
    iptables() { [ "$2" != "-D" ] && real_iptables "$@"; }
    run main rdp off
    [ "$status" -ne 0 ]
    output_has "did not close"
    [ "$(rdp_flag)" = "false" ]
}

# ---- Wi-Fi ----

@test "wifi-add: the network joins config.json with its password from the secret file, which is removed" {
    secret "correct horse"
    run main wifi-add Attic false --secret-file "${SECRET}"
    [ "$status" -eq 0 ]
    [ "$(config '.networkConfig.wifi.enable')" = true ]
    [ "$(config '.networkConfig.wifi.networks')" = '[{"ssid":"Attic","psk":"correct horse","hidden":false}]' ]
    [ ! -e "${SECRET}" ]
    [ "$(file_mode "${ROOT}/etc/kura/config.json")" = 600 ]
    file_has "${CALLS}" "systemctl restart kura-config.service"
    secret "another one!"
    run main wifi-add Attic true --secret-file "${SECRET}"
    [ "$(config '.networkConfig.wifi.networks | length')" = 1 ]
    [ "$(config '.networkConfig.wifi.networks[0].hidden')" = true ]
}

@test "wifi-add: a bad name or a password of the wrong length is refused" {
    secret "short"
    run main wifi-add Attic false --secret-file "${SECRET}"
    [ "$status" -ne 0 ]
    for name in ';evil' kura-ethernet; do
        secret "long enough"
        run main wifi-add "${name}" false --secret-file "${SECRET}"
        [ "$status" -ne 0 ]
    done
    run main wifi-add Attic false
    [ "$status" -ne 0 ]
    [ "$(config '.networkConfig.wifi.networks')" = null ]
}

@test "wifi-add: the password never appears on a command line" {
    secret "correct horse"
    jq() { [[ "$*" != *"correct horse"* ]] || echo leaked >> "${CALLS}"; command jq "$@"; }
    run main wifi-add Attic false --secret-file "${SECRET}"
    [ "$status" -eq 0 ]
    ! grep -q leaked "${CALLS}"
}

@test "config.json is never readable by others, even while it is rewritten" {
    grep -qx 'umask 077' "${BATS_TEST_DIRNAME}/../../packages/os-desktop/src/os-settings"
}

@test "wifi-remove: the network leaves config.json and NetworkManager" {
    secret "correct horse"
    main wifi-add Attic false --secret-file "${SECRET}"
    touch "${ROOT}/etc/NetworkManager/system-connections/Attic.nmconnection"
    run main wifi-remove Attic
    [ "$status" -eq 0 ]
    [ "$(config '.networkConfig.wifi.networks')" = '[]' ]
    [ ! -e "${ROOT}/etc/NetworkManager/system-connections/Attic.nmconnection" ]
    file_has "${CALLS}" "nmcli connection reload"
}

# ---- Ethernet ----

@test "ethernet static: recorded, applied, and set to go back unless confirmed" {
    run main ethernet static 192.168.1.50/24 192.168.1.1 192.168.1.1,9.9.9.9
    [ "$status" -eq 0 ]
    [ "$(config '.networkConfig.ethernet.ipv4')" = '{"method":"manual","address":"192.168.1.50/24","gateway":"192.168.1.1","dns":["192.168.1.1","9.9.9.9"]}' ]
    [ "$(jq -c . "${ROOT}/var/lib/kura/network-previous.json")" = '{"enable":true}' ]
    file_has "${CALLS}" "systemd-run --unit=kura-network-revert --on-active=120"
    file_has "${CALLS}" "systemctl restart kura-config.service"
    # the way back is armed before anything changes
    [ "$(grep -n 'systemd-run' "${CALLS}" | cut -d: -f1)" -lt "$(grep -n 'restart kura-config' "${CALLS}" | cut -d: -f1)" ]
}

@test "ethernet: the address is not changed when the way back cannot be armed" {
    systemd-run() { return 1; }
    run main ethernet static 192.168.1.50/24 192.168.1.1 192.168.1.1
    [ "$status" -ne 0 ]
    [ "$(config '.networkConfig.ethernet.ipv4')" = null ]
    [ ! -e "${ROOT}/var/lib/kura/network-previous.json" ]
}

@test "ethernet: going back restores the address only, not what else changed meanwhile" {
    main ethernet static 192.168.1.50/24 192.168.1.1 192.168.1.1
    main hostname attic
    run main network-revert
    [ "$status" -eq 0 ]
    [ "$(config '.networkConfig.ethernet')" = '{"enable":true}' ]
    [ "$(config .hostname)" = '"attic"' ]
}

@test "ethernet: without confirmation the earlier settings come back; with it they stay" {
    main ethernet static 192.168.1.50/24 192.168.1.1 192.168.1.1
    run main network-revert
    [ "$status" -eq 0 ]
    [ "$(config '.networkConfig.ethernet.ipv4')" = null ]
    [ ! -e "${ROOT}/var/lib/kura/network-previous.json" ]

    main ethernet static 192.168.1.50/24 192.168.1.1 192.168.1.1
    run main network-confirm
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "systemctl stop kura-network-revert.timer"
    run main network-revert
    [ "$(config '.networkConfig.ethernet.ipv4.method')" = '"manual"' ]
}

@test "ethernet auto: back to DHCP, also revertible" {
    main ethernet static 192.168.1.50/24 192.168.1.1 192.168.1.1
    main network-confirm
    run main ethernet auto
    [ "$status" -eq 0 ]
    [ "$(config '.networkConfig.ethernet.ipv4')" = '{"method":"auto"}' ]
    [ -f "${ROOT}/var/lib/kura/network-previous.json" ]
}

@test "ethernet static: addresses that are not addresses are refused" {
    for args in "192.168.1.50 192.168.1.1 1.1.1.1" "192.168.1.50/33 192.168.1.1 1.1.1.1" "192.168.1.256/24 192.168.1.1 1.1.1.1" \
        "192.168.1.50/24 gateway 1.1.1.1" "192.168.1.50/24 192.168.1.1 dns" "192.168.1.50/24 192.168.1.1" "0.0.0.0/0 0.0.0.0 0.0.0.0;x"; do
        # shellcheck disable=SC2086
        run main ethernet static ${args}
        [ "$status" -ne 0 ]
    done
    [ "$(config '.networkConfig.ethernet.ipv4')" = null ]
}

# ---- users ----

@test "user-add: a person with a home, a shell and the password from the secret file" {
    secret "s3cret pass"
    run main user-add carl false --secret-file "${SECRET}"
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "useradd --create-home --shell /bin/bash carl"
    [ "$(cat "${CALLS}.stdin")" = "carl:s3cret pass" ]
    ! grep -q gpasswd "${CALLS}"
    [ ! -e "${SECRET}" ]
    secret "s3cret pass"
    run main user-add dora true --secret-file "${SECRET}"
    file_has "${CALLS}" "gpasswd --add dora sudo"
}

@test "user-add: a name whose home folder is still there is refused (it holds someone's files)" {
    mkdir -p "${ROOT}/home/carl"
    secret "s3cret pass"
    run main user-add carl false --secret-file "${SECRET}"
    [ "$status" -ne 0 ]
    output_has "/home/carl"
    ! grep -q useradd "${CALLS}"
}

@test "user-add: a user whose password could not be set does not stay half made" {
    chpasswd() { cat > /dev/null; return 1; }
    secret "s3cret pass"
    run main user-add carl false --secret-file "${SECRET}"
    [ "$status" -ne 0 ]
    file_has "${CALLS}" "userdel --remove carl"
}

@test "a password with a line break never reaches chpasswd" {
    for name in bob carl; do
        printf 'x\nroot:pwned' > "${SECRET}"
        run main "$([ "${name}" = bob ] && echo user-password || echo user-add)" "${name}" $([ "${name}" = bob ] || echo false) --secret-file "${SECRET}"
        [ "$status" -ne 0 ]
    done
    [ ! -e "${CALLS}.stdin" ]
}

@test "user-add: an existing or badly named user, or an empty password, is refused" {
    for name in anna root Carl "c d" "-x" ""; do
        secret "s3cret pass"
        run main user-add "${name}" false --secret-file "${SECRET}"
        [ "$status" -ne 0 ]
    done
    secret ""
    run main user-add carl false --secret-file "${SECRET}"
    [ "$status" -ne 0 ]
    ! grep -q useradd "${CALLS}"
}

@test "user-password: a person's password is set; root's and system accounts' never" {
    secret "new pass"
    run main user-password bob --secret-file "${SECRET}"
    [ "$status" -eq 0 ]
    [ "$(cat "${CALLS}.stdin")" = "bob:new pass" ]
    for name in root daemon ghost; do
        secret "new pass"
        run main user-password "${name}" --secret-file "${SECRET}"
        [ "$status" -ne 0 ]
    done
    [ "$(wc -l < "${CALLS}.stdin" | tr -d ' ')" -le 1 ]
}

@test "user-admin: rights are given and taken, but never from the last administrator" {
    run main user-admin bob on
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "gpasswd --add bob sudo"
    run main user-admin anna off
    [ "$status" -ne 0 ]
    output_has "last administrator"
    printf 'sudo:x:27:anna,bob\n' > "${ROOT}/etc/group"
    run main user-admin anna off
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "gpasswd --delete anna sudo"
}

@test "user-remove: a person goes; the home stays, closed to whoever gets the uid next" {
    mkdir -p "${ROOT}/home/bob"
    run main user-remove bob
    [ "$status" -eq 0 ]
    file_has "${CALLS}" "pkill -KILL -u bob"
    file_has "${CALLS}" "userdel bob"
    ! grep -q -- "--remove" "${CALLS}"
    file_has "${CALLS}" "chown -R root:root ${ROOT}/home/bob"
    [ "$(file_mode "${ROOT}/home/bob")" = 700 ]
    for name in anna root daemon ghost; do
        run main user-remove "${name}"
        [ "$status" -ne 0 ]
    done
    [ "$(grep -c '^userdel' "${CALLS}")" -eq 1 ]
}

@test "an unknown command is refused" {
    run main format-disk
    [ "$status" -ne 0 ]
    run main
    [ "$status" -ne 0 ]
}
