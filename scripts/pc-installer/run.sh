#!/bin/bash
# scripts/pc-installer/run.sh
# The PC installer's whole run (ADR-017), sourced by install.sh: each state
# (network, release, target drive, confirmation, write, setup, done) redraws
# the screen with screen.sh and calls install.sh's steps. Defines functions
# only.
# shellcheck disable=SC2034  # STEP_INFO is drawn by screen.sh's show

# find_release: sets RELEASE_BUNDLE to "<url> <sha256> <extract-size>
# <extract-sha256>" of the latest PC image and fills the release step's
# detail (not in a subshell: it draws the screen)
find_release() {
    local url manifest status
    url=$(manifest_url "${CMDLINE_FILE}")
    show 3
    say "Reading the latest release from $(release_source "${url}") ..."
    manifest=$(mktemp) || return 1
    fetch_manifest "${url}" "${manifest}" && RELEASE_BUNDLE=$(manifest_bundle "${manifest}")
    status=$?
    STEP_INFO[2]=$(release_info "${manifest}")
    rm -f "${manifest}"
    [ "${status}" -eq 0 ] || fail "The list of Kura releases could not be read."
}

# release_source <manifest-url>: where releases come from, for the screen
release_source() {
    local where="${1#*://}"
    echo "${where%%/releases/*}"
}

# write_image <url> <sha256> <dev-name> <size> <extract-sha256>: the write,
# with its progress, and the read-back check
write_image() {
    local dev="${DEV_DIR}/$3" watcher status start=${SECONDS}
    show 5
    printf '%s' "${UI_SAVE}"
    progress_lines 0 "$4" 0
    echo
    say "The download is checked against the release (sha256), then the drive is read back."
    watch_progress "$3" "$4" &
    watcher=$!
    stream_image "$1" "$2" "${dev}" && sync
    status=$?
    kill "${watcher}" 2>/dev/null
    wait "${watcher}" 2>/dev/null
    # back to the progress, then below the note, where any error goes
    printf '%s' "${UI_RESTORE}"
    if [ "${status}" -eq 0 ]; then progress_lines "$4" "$4" $(( SECONDS - start )); else printf '\n\n'; fi
    printf '\n\n'
    [ "${status}" -eq 0 ] || return 1
    # flushbufs drops the cached pages, so the check reads the drive itself
    blockdev --flushbufs "${dev}" && verify_written "${dev}" "$4" "$5"
}

# finished <dev-name> <login>: the done screen
finished() {
    show 7
    ui_done "Kura is installed on $1."
    echo
    printf '%s%s1%s  Remove the USB key.\n' "${UI_PAD}" "$(ui_color F)" "$(ui_color 7)"
    printf '%s%s2%s  Turn the PC on: it starts Kura from the internal drive.\n' \
        "${UI_PAD}" "$(ui_color F)" "$(ui_color 7)"
    if [ -n "$2" ]; then
        printf '%s%s3%s  Log in as %s%s%s with SSH: Kura'"'"'s login screen shows the address and the command.\n' \
            "${UI_PAD}" "$(ui_color F)" "$(ui_color 7)" "$(ui_color D)" "$2" "$(ui_color 7)"
    else
        printf '%s%s3%s  Kura'"'"'s login screen shows the address and the SSH command.\n' \
            "${UI_PAD}" "$(ui_color F)" "$(ui_color 7)"
    fi
}

# install_kura <key-disk> <countdown-seconds>
install_kura() {
    local url sha size esha target dev bytes model login
    if already_installed; then
        ui_clear
        ui_header
        ui_warning "Kura is already installed from this key: remove the USB key and turn the PC on again."
        return 0
    fi
    STEP_INFO=("${INSTALLER_LABEL:+${INSTALLER_LABEL} on }$1" "" "" "" "" "$(setup_info)")
    login=$(setup_login)
    show 2
    say "Connecting to the wired network ..."
    net_up || fail "No network: plug in an Ethernet cable connected to the internet and try again." ||
        return 1
    STEP_INFO[1]=$(net_info)
    find_release || return 1
    read -r url sha size esha <<< "${RELEASE_BUNDLE}"

    show 4
    target=$(pick_target "$1" "${size}") || return 1
    read -r target bytes model <<< "${target}"
    dev="${DEV_DIR}/${target}"
    STEP_INFO[3]="${target} · ${model:-unknown drive} · $(gigabytes "${bytes}")"
    show 4
    ui_warning "Everything on ${target} (${model:-unknown drive}, $(gigabytes "${bytes}")) will be erased."
    echo
    countdown "$2" || { echo; say "Cancelled. Nothing was written."; return 1; }

    write_image "${url}" "${sha}" "${target}" "${size}" "${esha}" ||
        fail "Kura was not installed, and the drive will not boot until it is." || return 1
    show 6
    blockdev --rereadpt "${dev}" 2>/dev/null || true
    # The image's backup GPT sits where the image ended, not at the disk's end
    sfdisk --relocate gpt-bak-std "${dev}" 2>/dev/null || true
    blockdev --rereadpt "${dev}" 2>/dev/null || true
    with_mount "${DEV_DIR}/$(disk_partition "${target}" 1)" hand_over_setup -t vfat ||
        fail "Kura was installed, but its setup could not be copied." || return 1
    mark_installed
    finished "${target}" "${login}"
}
