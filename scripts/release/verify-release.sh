#!/bin/bash
# scripts/release/verify-release.sh <asset> <tag>
#
# Verifies that a downloaded Kura release asset (image, SHA512SUMS or
# manifest.json) was signed by Kura's release pipeline for release <tag>
# (e.g. v0.1.0). Expects the asset's bundle next to it as
# <asset>.sigstore.json (published with every release). Needs cosign.

set -euo pipefail

ASSET="${1:?Usage: $0 <asset> <tag>}"
TAG="${2:?Usage: $0 <asset> <tag>}"
REPO="${KURA_RELEASE_REPO:-cbabil/kura}"
WORKFLOW="release.yml"

# shellcheck disable=SC1091
source "$(dirname "$0")/../common/sigstore.sh"

sigstore_verify "${ASSET}" "${ASSET}.sigstore.json" "${REPO}" "${WORKFLOW}" "${TAG}"
echo "OK: ${ASSET} was signed by ${REPO}'s release pipeline for ${TAG}."
