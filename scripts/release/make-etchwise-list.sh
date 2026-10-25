#!/bin/bash
# scripts/release/make-etchwise-list.sh <manifest.json>
#
# Prints etchwise.json: the OS list Etchwise reads for Kura (Raspberry Pi
# Imager's v4 format, as a sublist), built from the release manifest: the Pi 5
# image and the PC image (Intel NUC and other x86-64 machines). init_format
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
        entry(.bundles["x86_64"]; "Kura \(.version) (PC)";
            "Lightweight home-server OS for UEFI PCs such as the Intel NUC: write it to a USB drive or SSD and boot from it"; "x86-64")
    ]}' "${MANIFEST}"
