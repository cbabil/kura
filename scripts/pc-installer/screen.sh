#!/bin/bash
# scripts/pc-installer/screen.sh
# What install.sh shows while it runs (ADR-017): the details beside each
# step, the confirmation countdown and the write progress, drawn with ui.sh.
# The progress reads the target's /sys/block/<dev>/stat, under SYS_BLOCK so
# the tests can fake it. Source this file; it defines functions only.

# shellcheck source=SCRIPTDIR/ui.sh
source "$(dirname "${BASH_SOURCE[0]}")/ui.sh"

SYS_BLOCK="${SYS_BLOCK:-/sys/block}"
# The detail beside each step of ui_steps, filled as the install goes
STEP_INFO=("" "" "" "" "" "")
PROGRESS_WIDTH=76
COUNTDOWN_WIDTH=40

# show <current-step>: the whole screen up to the steps; callers add the rest
show() {
    ui_clear
    ui_header
    ui_steps "$1" "${STEP_INFO[@]}"
    echo
}

megabytes() { echo "$(( $1 / 1000000 )) MB"; }

# tenths_gb <bytes>: "2.1 GB"
tenths_gb() {
    local tenths=$(( $1 / 100000000 ))
    echo "$(( tenths / 10 )).$(( tenths % 10 )) GB"
}

# net_info: "<interface> · <IPv4>" of the first global address, or nothing
net_info() {
    local _index dev _family addr
    read -r _index dev _family addr _ < <(ip -o -4 addr show scope global 2>/dev/null) || return 0
    [ -n "${addr}" ] && echo "${dev} · ${addr%/*}"
}

# release_info <manifest>: "Kura <version> · <download size>"
release_info() {
    local version size
    read -r version size < <(jq -r '"\(.version) \(.bundles.x86_64.size)"' "$1" 2>/dev/null)
    [[ "${size}" =~ ^[0-9]+$ ]] || size=0
    echo "Kura ${version#v} · $(megabytes "${size}") download"
}

# setup_info: what the key's setup file hands over to Kura's first boot
setup_info() {
    local file="${KEY_DIR}/${INSTALLER_SETUP_FILE}"
    [ -f "${file}" ] || { echo "no setup file on the key"; return 0; }
    jq -r '[ (.user.name // empty | "user " + .),
             (if ((.ssh.authorizedKeys // []) | length) > 0 then "SSH key" else empty end),
             (.hostname // empty | "hostname " + .),
             (.wifi.ssid // empty | "Wi-Fi") ] | join(", ")' "${file}" 2>/dev/null
}

# setup_login: "<user>@<hostname>.local" from the setup file, or nothing
setup_login() {
    jq -r 'select(.user.name and .hostname) | "\(.user.name)@\(.hostname).local"' \
        "${KEY_DIR}/${INSTALLER_SETUP_FILE}" 2>/dev/null || true
}

# countdown <seconds>: the seconds left over a shrinking bar; fails as soon
# as a key is pressed
countdown() {
    local left
    printf '%s' "${UI_SAVE}"    # each tick redraws from here
    for (( left = $1; left > 0; left-- )); do
        printf '%s%s%sInstalling in %s%d%s seconds   %s\033[K\n' "${UI_RESTORE}" "${UI_PAD}" "$(ui_color 7)" \
            "$(ui_color F)" "${left}" "$(ui_color 7)" "$(ui_bar "${left}" "$1" "${COUNTDOWN_WIDTH}")"
        ui_note "Press any key to cancel. Nothing has been written yet."
        if read -r -s -n 1 -t 1 _; then
            return 1
        fi
    done
}

# written_bytes <dev-name>: bytes the drive has written since it appeared
# (the 7th field of its stat counts 512-byte sectors), 0 if unknown
written_bytes() {
    local fields
    read -r -a fields 2>/dev/null < "${SYS_BLOCK}/$1/stat" || { echo 0; return 0; }
    echo $(( ${fields[6]:-0} * 512 ))
}

# progress_lines <written> <total> <seconds>: the bar with its percent, then
# GB written of the image, the average rate and the time left
progress_lines() {
    local written=$1 total=$2 secs=$3 percent=0 stats rate left
    [ "${written}" -gt "${total}" ] && written=${total}
    [ "${total}" -gt 0 ] && percent=$(( 100 * written / total ))
    printf '%s%s  %s%d%%\033[K\n' "${UI_PAD}" "$(ui_bar "${written}" "${total}" "${PROGRESS_WIDTH}")" \
        "$(ui_color F)" "${percent}"
    stats="$(tenths_gb "${written}") of $(tenths_gb "${total}") written"
    if [ "${written}" -gt 0 ] && [ "${secs}" -gt 0 ]; then
        rate=$(( written / secs / 1000000 ))
        left=$(( (total - written) * secs / written ))
        if [ "${left}" -lt 90 ]; then left="${left} s"; else left="$(( left / 60 )) min"; fi
        stats+=" · ${rate} MB/s · about ${left} left"
    fi
    printf '%s%s%s\033[K\n' "${UI_PAD}" "$(ui_color 8)" "${stats}"
}

# watch_progress <dev-name> <image-bytes>: redraws the progress every second
# from the cursor position saved before it started (ESC 7), until killed
watch_progress() {
    local base start=${SECONDS}
    base=$(written_bytes "$1")
    while :; do
        printf '%s' "${UI_RESTORE}"
        progress_lines $(( $(written_bytes "$1") - base )) "$2" $(( SECONDS - start ))
        sleep 1
    done
}
