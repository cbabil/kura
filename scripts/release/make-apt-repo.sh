#!/bin/bash
# scripts/release/make-apt-repo.sh
# Makes a folder of .deb files a flat apt repository (ADR-025): Packages,
# Release and, with a signing key, InRelease. Published as release assets,
# devices read it at https://github.com/<repo>/releases/latest/download/
# (scripts/common/kura-repo.sh).
#
# Usage: make-apt-repo.sh <dir> [signing-key-fingerprint]
# Needs dpkg-scanpackages (dpkg-dev); gpg with the secret key to sign.

set -euo pipefail

DIR="${1:?Usage: $0 <dir> [signing-key-fingerprint]}"
KEY="${2:-}"

# shellcheck source=scripts/common/hash.sh
source "$(dirname "${BASH_SOURCE[0]}")/../common/hash.sh"

cd "${DIR}"
compgen -G "./*.deb" >/dev/null || { echo "ERROR: no .deb files in ${DIR}" >&2; exit 1; }

dpkg-scanpackages --multiversion . > Packages 2>/dev/null
[ -s Packages ] || { echo "ERROR: dpkg-scanpackages listed nothing" >&2; exit 1; }

archs=$(for f in ./*.deb; do f="${f%.deb}"; echo "${f##*_}"; done | sort -u | tr '\n' ' ')

cat > Release <<RELEASE
Origin: Kura
Label: Kura
Suite: stable
Codename: kura
Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')
Architectures: ${archs% }
Description: Kura's own packages
SHA256:
 $(file_sha256 Packages) $(wc -c < Packages | tr -d ' ') Packages
RELEASE

if [ -n "${KEY}" ]; then
    gpg --batch --yes --pinentry-mode loopback --passphrase '' --local-user "${KEY}" \
        --digest-algo SHA512 --clearsign --output InRelease Release
fi
