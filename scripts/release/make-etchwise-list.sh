#!/bin/bash
# scripts/release/make-etchwise-list.sh <manifest.json>
#
# Prints etchwise.json: the OS list Etchwise reads for Kura (Raspberry Pi
# Imager's v4 format, as a sublist), built from the release manifest. One Pi 5
# entry; init_format "kura" makes Etchwise write kura-setup.json, which first
# boot applies (scripts/common/firstboot-setup.sh). The x86 ISO is live-only,
# so it is not listed. Needs jq.

set -euo pipefail

[ $# -eq 1 ] || { echo "Usage: $0 <manifest.json>" >&2; exit 2; }
MANIFEST="$1"
[ -f "${MANIFEST}" ] || { echo "ERROR: manifest not found: ${MANIFEST}" >&2; exit 1; }

ICON="data:image/svg+xml;base64,$(base64 < "$(dirname "$0")/kura-icon.svg" | tr -d '\n')"

jq --arg icon "${ICON}" '.bundles["rpi5-arm64"] as $b | {os_list: [{
    name: "Kura \(.version)",
    description: "Lightweight home-server OS: Debian 13, Docker, hardened by default",
    icon: $icon,
    url: $b.url,
    extract_size: $b.extract_size,
    extract_sha256: $b.extract_sha256,
    image_download_size: $b.size,
    image_download_sha256: $b.sha256,
    release_date: .released,
    init_format: "kura",
    devices: ["pi5-64bit"],
    capabilities: []
}]}' "${MANIFEST}"
