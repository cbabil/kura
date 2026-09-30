#!/bin/bash
# scripts/release/make-manifest.sh <tag> <owner/repo> <pi-image> <iso>
#
# Prints the release manifest (projects-docs/kura/architecture/updates.md, section 2)
# for one Kura release: version, channel, release date, and the download
# url/sha256/size of each image. The release workflow signs it next to the
# images. Needs jq.

set -euo pipefail

TAG="${1:?Usage: $0 <tag> <owner/repo> <pi-image> <iso>}"
REPO="${2:?Usage: $0 <tag> <owner/repo> <pi-image> <iso>}"
PI_IMAGE="${3:?Usage: $0 <tag> <owner/repo> <pi-image> <iso>}"
ISO="${4:?Usage: $0 <tag> <owner/repo> <pi-image> <iso>}"

# shellcheck disable=SC1091
source "$(dirname "$0")/../common/hash.sh"

# asset <file>: url/sha256/size of one release asset, as JSON
asset() {
    jq -n --arg url "https://github.com/${REPO}/releases/download/${TAG}/$(basename "$1")" \
          --arg sha256 "$(file_sha256 "$1")" \
          --argjson size "$(wc -c < "$1" | tr -d ' ')" \
          '{url: $url, sha256: $sha256, size: $size}'
}

jq -n --arg version "${TAG#v}" \
      --arg released "$(date -u +%Y-%m-%d)" \
      --argjson rpi "$(asset "${PI_IMAGE}")" \
      --argjson x86 "$(asset "${ISO}")" \
      '{version: $version, channel: "stable", released: $released,
        bundles: {"rpi5-arm64": $rpi, "x86_64": $x86}}'
