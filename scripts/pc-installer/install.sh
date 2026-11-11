#!/bin/bash
# scripts/pc-installer/install.sh
# The PC installer's steps (ADR-017), run from RAM by init: find the latest
# Kura PC image in the release manifest, pick the one internal disk, write
# the image to it with both checksums checked, hand over kura-setup.json and
# mark the USB key as used. Paths come from SYS_BLOCK, DEV_DIR, KEY_DIR and
# CMDLINE_FILE so the tests can fake them. The screen is redrawn whole for
# each state (screen.sh, ui.sh). Defines functions only.

# shellcheck disable=SC1091
source "${INSTALLER_COMMON:-$(dirname "${BASH_SOURCE[0]}")/../common}/firstboot-disk.sh"
# shellcheck source=SCRIPTDIR/screen.sh
source "$(dirname "${BASH_SOURCE[0]}")/screen.sh"
# shellcheck source=SCRIPTDIR/run.sh
source "$(dirname "${BASH_SOURCE[0]}")/run.sh"

DEV_DIR="${DEV_DIR:-/dev}"
KEY_DIR="${KEY_DIR:-/run/key}"
CMDLINE_FILE="${CMDLINE_FILE:-/proc/cmdline}"
INSTALLER_SETUP_FILE="${INSTALLER_BRAND:-kura}-setup.json"
INSTALLED_MARK=".installed"
LATEST_MANIFEST="https://github.com/${KURA_RELEASE_REPO:-cbabil/kura}/releases/latest/download/manifest.json"
SHA256_RE='^[0-9a-f]{64}$'

say() { ui_note "$*"; }
fail() { ui_error "$*" >&2; return 1; }

# gigabytes <bytes>: whole decimal GB, as drives are sold
gigabytes() { echo "$(( $1 / 1000000000 )) GB"; }

# wired_ifaces: network interfaces other than loopback and Wi-Fi
wired_ifaces() {
    local dir
    for dir in /sys/class/net/*; do
        [ "${dir##*/}" = lo ] || [ -d "${dir}/wireless" ] || echo "${dir##*/}"
    done
}

# net_up: a DHCP lease on the first wired interface that gets one
net_up() {
    local dev
    for dev in $(wired_ifaces); do ip link set "${dev}" up; done
    sleep 3    # link negotiation
    for dev in $(wired_ifaces); do
        udhcpc -i "${dev}" -n -q -t 5 -T 3 -s "${INSTALLER_COMMON}/udhcpc.script" >/dev/null 2>&1 &&
            return 0
    done
    return 1
}

# ---- Release manifest ----

# manifest_url <cmdline-file>: kura.manifest=<url> from the kernel command
# line (the boot test serves its own image), else the latest release
manifest_url() {
    local word
    for word in $(cat "$1" 2>/dev/null); do
        case "${word}" in
            kura.manifest=?*) echo "${word#kura.manifest=}"; return 0 ;;
        esac
    done
    echo "${LATEST_MANIFEST}"
}

# fetch_manifest <url> <file>
fetch_manifest() { curl -fsSL --retry 3 -o "$2" "$1"; }

# manifest_bundle <file>: "<url> <sha256> <extract-size> <extract-sha256>" of
# the PC image (scripts/release/make-manifest.sh); fails on anything missing
manifest_bundle() {
    local line url sha size esha
    line=$(jq -er '.bundles.x86_64 | [.url, .sha256, (.extract_size | tostring), .extract_sha256]
        | join(" ")' "$1" 2>/dev/null) || return 1
    read -r url sha size esha <<< "${line}"
    [[ "${url}" =~ ^https?:// ]] && [[ "${sha}" =~ ${SHA256_RE} ]] &&
        [[ "${size}" =~ ^[0-9]+$ ]] && [[ "${esha}" =~ ${SHA256_RE} ]] || return 1
    echo "${line}"
}

# ---- Target disk ----

# disk_candidates <key-disk> <min-bytes>: "<name> <bytes> <model>" for each
# whole disk that could hold Kura: not the key, not removable media, nothing
# behind USB (an external drive says it is not removable), no SD card, not a
# virtual or eMMC boot device, and big enough
disk_candidates() {
    local dir name removable sectors model
    for dir in "${SYS_BLOCK}"/*; do
        name="${dir##*/}"
        case "${name}" in
            loop*|ram*|zram*|sr*|dm-*|md*|nbd*|*boot[0-9]|*rpmb|"$1") continue ;;
        esac
        case "$(readlink -f "${dir}")" in */usb[0-9]*) continue ;; esac
        # An SD card in a built-in reader is a card, not a drive (eMMC is MMC)
        [ "$(cat "${dir}/device/type" 2>/dev/null)" = SD ] && continue
        read -r removable < "${dir}/removable" 2>/dev/null || continue
        [ "${removable}" = 0 ] || continue
        read -r sectors < "${dir}/size" 2>/dev/null || continue
        [ $(( sectors * 512 )) -ge "$2" ] || continue
        model=""
        read -r model < "${dir}/device/model" 2>/dev/null || true
        echo "${name} $(( sectors * 512 )) ${model}"
    done
}

# pick_target <key-disk> <min-bytes>: the one candidate's "<name> <bytes>
# <model>"; with none or several, says so and fails (nothing is written)
pick_target() {
    local found count
    found=$(disk_candidates "$1" "$2")
    count=$(grep -c . <<< "${found}")
    if [ "${count}" -eq 0 ]; then
        fail "No internal drive of at least $(gigabytes "$2") was found."
    elif [ "${count}" -gt 1 ]; then
        fail "More than one internal drive was found; disconnect all but the one for Kura:" \
            "$(echo; while read -r name bytes model; do
                echo "  ${name}: ${model} ($(gigabytes "${bytes}"))"
            done <<< "${found}")"
    else
        echo "${found}"
    fi
}

# ---- Writing ----

# stream_image <url> <sha256> <target>: download, decompress and write in one
# pass, checking the download against <sha256>
stream_image() {
    local dir codes sum
    dir=$(mktemp -d) || return 1
    mkfifo "${dir}/data"
    sha256sum < "${dir}/data" | cut -d' ' -f1 > "${dir}/sum" &
    curl -fsSL --retry 3 "$1" | tee "${dir}/data" | zstd -q -dc > "$3"
    codes="${PIPESTATUS[*]}"
    wait $!
    read -r sum < "${dir}/sum"
    rm -rf "${dir}"
    [ "${codes}" = "0 0 0" ] || fail "The download failed."
    [ "${sum}" = "$2" ] || fail "The download does not match its checksum."
}

# verify_written <target> <size> <sha256>: the first <size> bytes on the disk
verify_written() {
    [ "$(head -c "$2" "$1" | sha256sum | cut -d' ' -f1)" = "$3" ] ||
        fail "The drive does not read back what was written."
}

# ---- The key and the setup file ----

# hand_over_setup <efi-dir>: Etchwise's setup file, for Kura's first boot
hand_over_setup() {
    [ -f "${KEY_DIR}/${INSTALLER_SETUP_FILE}" ] || return 0
    cp "${KEY_DIR}/${INSTALLER_SETUP_FILE}" "$1/"
}

# mark_installed: the key will not install again, then the setup file
# (password hash, Wi-Fi key) is overwritten and removed, in that order so a
# power cut never leaves a key that reinstalls without the setup
mark_installed() {
    local setup="${KEY_DIR}/${INSTALLER_SETUP_FILE}"
    : > "${KEY_DIR}/${INSTALLED_MARK}"
    sync
    if [ -f "${setup}" ]; then
        wipe_file "${setup}"
        rm -f "${setup}"
        sync
    fi
}

already_installed() { [ -e "${KEY_DIR}/${INSTALLED_MARK}" ]; }
