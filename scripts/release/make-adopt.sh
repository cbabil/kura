#!/bin/bash
# scripts/release/make-adopt.sh
# Prints kura-adopt.sh (ADR-025), the one-time script for devices installed
# before Kura had packages: scripts/release/kura-adopt.in with the
# repository's key, source and pin inside, exactly as install_kura_repo
# (scripts/common/kura-repo.sh) puts them in every new image.
#
# Usage: make-adopt.sh <brand> <owner/repo> [<url> <key-file> <fingerprint>]
#        > kura-adopt.sh
# The optional arguments name another repository and its key: the upgrade
# test's own, signed with a throwaway key.

set -euo pipefail

BRAND="${1:?Usage: $0 <brand> <owner/repo> [<url> <key-file> <fingerprint>]}"
REPO="${2:?Usage: $0 <brand> <owner/repo> [<url> <key-file> <fingerprint>]}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=scripts/common/kura-repo.sh
source "${HERE}/../common/kura-repo.sh"
# shellcheck source=scripts/common/brand-defaults.sh
source "${HERE}/../common/brand-defaults.sh"

stage=$(mktemp -d)
trap 'rm -rf "${stage}"' EXIT
install_kura_repo "${stage}" "${BRAND}" "${REPO}" "${@:3}"
url=$(sed -n 's/^URIs: //p' "${stage}/etc/apt/sources.list.d/${BRAND}.sources")
# one "<path> <base64>" per file, joined for sed with a marker for the newlines
files=$(cd "${stage}" && find usr etc -type f | sort | while read -r f; do
    printf '%s %s@@' "${f}" "$(base64 < "${f}" | tr -d '\n')"
done)

sed -e "s|__BRAND_NAME__|${OS_NAME:-${DEFAULT_NAME}}|g" -e "s|__BRAND__|${BRAND}|g" -e "s|__URL__|${url}|g" \
    -e "s|__FILES__|${files}|" "${HERE}/kura-adopt.in" | awk '{ gsub(/@@/, "\n"); print }'
