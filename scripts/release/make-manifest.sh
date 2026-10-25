#!/bin/bash
# scripts/release/make-manifest.sh <tag> <owner/repo> <pi-image> <pc-image>
#
# Prints the release manifest (projects-docs/kura/architecture/updates.md, section 2)
# for one Kura release: version, channel, release date, and the download
# url/sha256/size of each image, plus the unpacked image's size and sha256
# (what an imager writes and verifies). The release workflow signs it next to
# the images. Needs jq, and zstd for a .zst image.

set -euo pipefail

[ $# -eq 4 ] || { echo "Usage: $0 <tag> <owner/repo> <pi-image> <pc-image>" >&2; exit 2; }
TAG="$1" REPO="$2" PI_IMAGE="$3" PC_IMAGE="$4"

# shellcheck disable=SC1091
source "$(dirname "$0")/../common/hash.sh"

# asset <file>: url/sha256/size of one release asset and of its unpacked
# image, as JSON. A .zst image is decompressed once; anything else is
# written as it is, so its unpacked hash is its own.
asset() {
    local sha256 size extract_sha256 extract_size tmp
    sha256=$(file_sha256 "$1")
    size=$(wc -c < "$1" | tr -d ' ')
    extract_sha256="${sha256}" extract_size="${size}"
    if [[ "$1" == *.zst ]]; then
        tmp=$(mktemp -d)
        mkfifo "${tmp}/unpacked"
        file_sha256 - < "${tmp}/unpacked" > "${tmp}/sha256" &
        extract_size=$(zstd -dc -- "$1" | tee "${tmp}/unpacked" | wc -c | tr -d ' ')
        wait "$!"
        extract_sha256=$(cat "${tmp}/sha256")
        rm -rf "${tmp}"
    fi
    jq -n --arg url "https://github.com/${REPO}/releases/download/${TAG}/$(basename "$1")" \
          --arg sha256 "${sha256}" --argjson size "${size}" \
          --arg extract_sha256 "${extract_sha256}" --argjson extract_size "${extract_size}" \
          '{url: $url, sha256: $sha256, size: $size,
            extract_sha256: $extract_sha256, extract_size: $extract_size}'
}

jq -n --arg version "${TAG#v}" \
      --arg released "$(date -u +%Y-%m-%d)" \
      --argjson rpi "$(asset "${PI_IMAGE}")" \
      --argjson x86 "$(asset "${PC_IMAGE}")" \
      '{version: $version, channel: "stable", released: $released,
        bundles: {"rpi5-arm64": $rpi, "x86_64": $x86}}'
