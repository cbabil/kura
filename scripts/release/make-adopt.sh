#!/bin/bash
# scripts/release/make-adopt.sh
# Prints kura-adopt.sh (ADR-025), the one-time script for devices installed
# before Kura had packages: scripts/release/kura-adopt.in with the
# repository's key, source and pin inside, exactly as install_kura_repo
# (scripts/common/kura-repo.sh) puts them in every new image.
#
# Usage: make-adopt.sh <brand> <owner/repo> > kura-adopt.sh
# KURA_REPO_URL, KURA_KEY_FILE and KURA_GPG_FINGERPRINT override the
# repository (the upgrade test serves its own, signed with a throwaway key).

set -euo pipefail

BRAND="${1:?Usage: $0 <brand> <owner/repo>}"
REPO="${2:?Usage: $0 <brand> <owner/repo>}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
key_file="${KURA_KEY_FILE:-}" fingerprint="${KURA_GPG_FINGERPRINT:-}"

# shellcheck source=scripts/common/kura-repo.sh
source "${HERE}/../common/kura-repo.sh"
KURA_KEY_FILE="${key_file:-${KURA_KEY_FILE}}"
KURA_GPG_FINGERPRINT="${fingerprint:-${KURA_GPG_FINGERPRINT}}"

stage=$(mktemp -d)
trap 'rm -rf "${stage}"' EXIT
install_kura_repo "${stage}" "${BRAND}" "${REPO}"
url=$(sed -n 's/^URIs: //p' "${stage}/etc/apt/sources.list.d/${BRAND}.sources")
files=$(tar -czf - -C "${stage}" usr etc | base64 | tr -d '\n')

name="$(tr '[:lower:]' '[:upper:]' <<< "${BRAND:0:1}")${BRAND:1}"
sed -e "s|__BRAND_NAME__|${name}|g" -e "s|__BRAND__|${BRAND}|g" -e "s|__URL__|${url}|g" \
    -e "s|__FILES__|${files}|" "${HERE}/kura-adopt.in"
