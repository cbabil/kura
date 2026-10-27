#!/bin/bash
# scripts/release/make-etchwise-list.sh <manifest.json>
#
# Prints etchwise.json: the OS list Etchwise reads for Kura (Raspberry Pi
# Imager's v4 format, as a sublist), built from the release manifest: the Pi 5
# image, the PC installer (ADR-017: writes Kura to the PC's internal drive)
# and the PC image (runs from the drive it is written to). init_format
# "kura" makes Etchwise write kura-setup.json, which first boot applies
# (scripts/common/firstboot-setup.sh). Needs jq.

set -euo pipefail

[ $# -eq 1 ] || { echo "Usage: $0 <manifest.json>" >&2; exit 2; }
MANIFEST="$1"
[ -f "${MANIFEST}" ] || { echo "ERROR: manifest not found: ${MANIFEST}" >&2; exit 1; }

ICON="data:image/svg+xml;base64,$(base64 < "$(dirname "$0")/kura-icon.svg" | tr -d '\n')"

jq --arg icon "${ICON}" '
    def entry($b; $name; $description; $device): {
        name: $name, description: $description, icon: $icon, url: $b.url,
        extract_size: $b.extract_size, extract_sha256: $b.extract_sha256,
        image_download_size: $b.size, image_download_sha256: $b.sha256,
        release_date: .released, init_format: "kura", devices: [$device], capabilities: []
    };
    {os_list: [
        entry(.bundles["rpi5-arm64"]; "Kura \(.version)";
            "Lightweight home-server OS: Debian 13, Docker, hardened by default"; "pi5-64bit"),
        entry(.installers["x86_64"]; "Kura \(.version) installer (PC)";
            "Small USB installer: boot the PC from it with an Ethernet cable plugged in and it installs Kura on the internal drive"; "x86-64"),
        entry(.bundles["x86_64"]; "Kura \(.version) (PC)";
            "Kura for UEFI PCs such as the Intel NUC, run from the drive it is written to (a USB drive or SSD)"; "x86-64")
    ]}' "${MANIFEST}"
