#!/bin/bash
# scripts/common/firstboot-setup-check.sh
# Validation of __BRAND__-setup.json (format in firstboot-setup.sh, which
# sources this file). Every field is checked before anything is applied;
# messages name the field, never its value. Defines functions only.

# shellcheck disable=SC2016  # jq programs are single-quoted on purpose

SETUP_MAX_BYTES=65536
USER_RE='^[a-z_][a-z0-9_-]{0,31}$'
HOST_RE='^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$'
HASH_RE='^\$[a-z0-9]+\$[^:[:space:]]+$'
KEY_RE='^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh\.com) [A-Za-z0-9+/]+=*( [[:print:]]*)?$'
SSID_RE='^[a-zA-Z0-9][a-zA-Z0-9 _.-]*$'   # os-config's SAFE_SSID_RE (a test keeps them equal)
PSK_RE='^([0-9a-fA-F]{64}|[[:print:]]{8,63})$'
COUNTRY_RE='^[A-Z]{2}$'
TZ_RE='^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+){0,2}$'
KEYBOARD_RE='^[a-z]{2,8}(,[a-z]{2,8})*$'

# The last error, kept for the login screen's setup line (setup-status,
# written by firstboot-setup.sh)
SETUP_LAST_ERROR=""
# shellcheck disable=SC2034
setup_error() { SETUP_LAST_ERROR="$*"; echo "ERROR: setup: $*" >&2; }

# setup_get <file> <jq-path>: the value, or nothing when null or missing
setup_get() { jq -r "($2) | if . == null then empty else . end" "$1"; }

# setup_has <file> <key>: the top-level key is present
setup_has() { jq -e --arg k "$2" 'has($k)' "$1" >/dev/null; }

# setup_check <value> <regex> <what>: empty values pass (key left out)
setup_check() {
    [ -z "$1" ] || [[ "$1" =~ $2 ]] || { setup_error "invalid $3"; return 1; }
}

# setup_types <file> <checks>: the first field whose type is wrong, if any;
# checks are jq `want(path; type; name)` calls
setup_types() {
    jq -r "def want(p; t; n): (try (p | type) catch \"error\") as \$x
        | if \$x == t or \$x == \"null\" then empty else n end; [$2] | first // empty" "$1"
}

# name_taken <name>: a passwd or group entry other than the login user's own
name_taken() {
    local entry
    entry=$(getent passwd "$1") && [ "$(cut -d: -f3 <<< "${entry}")" != "${LOGIN_UID}" ] && return 0
    entry=$(getent group "$1") && [ "$(cut -d: -f3 <<< "${entry}")" != "${LOGIN_UID}" ]
}

# validate_setup <file>: everything except the Wi-Fi (see validate_wifi)
validate_setup() {
    local f="$1" bad name key
    [ "$(wc -c < "${f}")" -le "${SETUP_MAX_BYTES}" ] || { setup_error "file too large"; return 1; }
    jq -e 'type == "object"' "${f}" >/dev/null 2>&1 || { setup_error "not a JSON object"; return 1; }
    jq -e '.version == 1' "${f}" >/dev/null || { setup_error "unsupported version"; return 1; }
    bad=$(setup_types "${f}" 'want(.hostname; "string"; "hostname"), want(.user; "object"; "user"),
        want(.user.name; "string"; "user name"), want(.user.passwordHash; "string"; "password"),
        want(.ssh; "object"; "ssh"), want(.ssh.enabled; "boolean"; "ssh.enabled"),
        want(.ssh.passwordAuth; "boolean"; "ssh.passwordAuth"),
        want(.ssh.authorizedKeys; "array"; "ssh.authorizedKeys"),
        want(.timezone; "string"; "time zone"), want(.keyboard; "string"; "keyboard")')
    [ -z "${bad}" ] || { setup_error "${bad} has the wrong type"; return 1; }
    jq -e '[.ssh.authorizedKeys[]? | select(type != "string" or . == "" or test("[[:cntrl:]]"))]
        | length == 0' "${f}" >/dev/null || { setup_error "invalid SSH key"; return 1; }
    jq -e '.ssh == null or .ssh.enabled == false or .ssh.passwordAuth != false
        or (.ssh.authorizedKeys | length) > 0' "${f}" >/dev/null ||
        { setup_error "SSH without passwords or keys leaves no way to log in"; return 1; }

    name=$(setup_get "${f}" .user.name)
    if setup_has "${f}" user && [ -z "${name}" ]; then
        setup_error "missing user name"; return 1
    fi
    setup_check "${name}" "${USER_RE}" "user name" || return 1
    if [ -n "${name}" ] && name_taken "${name}"; then
        setup_error "invalid user name (taken by a system account or group)"; return 1
    fi
    setup_check "$(setup_get "${f}" .hostname)" "${HOST_RE}" "hostname" &&
    setup_check "$(setup_get "${f}" .user.passwordHash)" "${HASH_RE}" "password hash" &&
    setup_check "$(setup_get "${f}" .timezone)" "${TZ_RE}" "time zone" &&
    setup_check "$(setup_get "${f}" .keyboard)" "${KEYBOARD_RE}" "keyboard" || return 1
    while IFS= read -r key; do
        setup_check "${key}" "${KEY_RE}" "SSH key" || return 1
    done < <(jq -r '.ssh.authorizedKeys[]?' "${f}")
}

# validate_wifi <file>: a bad Wi-Fi section is skipped, not the whole file
validate_wifi() {
    local f="$1" bad
    bad=$(setup_types "${f}" 'want(.wifi; "object"; "wifi"), want(.wifi.ssid; "string"; "SSID"),
        want(.wifi.psk; "string"; "Wi-Fi password"), want(.wifi.hidden; "boolean"; "wifi.hidden"),
        want(.wifi.country; "string"; "country")')
    [ -z "${bad}" ] || { setup_error "${bad} has the wrong type"; return 1; }
    [ -n "$(setup_get "${f}" .wifi.ssid)" ] || { setup_error "missing SSID"; return 1; }
    [ -n "$(setup_get "${f}" .wifi.psk)" ] || { setup_error "missing Wi-Fi password"; return 1; }
    setup_check "$(setup_get "${f}" .wifi.ssid)" "${SSID_RE}" "SSID" &&
    setup_check "$(setup_get "${f}" .wifi.psk)" "${PSK_RE}" "Wi-Fi password" &&
    setup_check "$(setup_get "${f}" .wifi.country)" "${COUNTRY_RE}" "country"
}
