#!/bin/bash
# scripts/common/fetch-tomo.sh
# Fetches the pinned Tomo release .deb that gets installed into the image.
#
# Kura installs Tomo's published release package (not a source build), so the
# image carries exactly what the .deb channel ships. The version and its
# sha256 per architecture are pinned here and can be overridden from .env:
#
#   OS_TOMO_VERSION        release to install (x.y.z)
#   OS_TOMO_SHA256_ARM64   sha256 of tomo_<ver>_arm64.deb (required if version changes)
#   OS_TOMO_SHA256_AMD64   sha256 of tomo_<ver>_amd64.deb (required if version changes)
#   OS_TOMO_DEB            path to a local .deb (development; skips download + checksum)
#
# Source this file; it defines functions only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/sigstore.sh"

TOMO_REPO="cbabil/tomo"
TOMO_RELEASE_WORKFLOW="release.yml"
# First Tomo release signed by its release workflow (cbabil/tomo#51). From this
# version on, a missing signature bundle fails the build instead of warning.
TOMO_SIGNED_SINCE="${TOMO_SIGNED_SINCE:-0.0.77}"

# Pinned release. Checksums match checksums.sha256 published with the release.
# shellcheck disable=SC2034
TOMO_DEFAULT_VERSION="0.0.76"
# shellcheck disable=SC2034  # read indirectly by tomo_expected_sha
TOMO_DEFAULT_SHA256_ARM64="98ac606bbe0529843e1b3b9c2bd72901eb8e4e958e4c07df8d79ae06ec926aef"
# shellcheck disable=SC2034
TOMO_DEFAULT_SHA256_AMD64="3cc04b78ed567b96bfc7383641119cd75affcbe0556e2c53ad9604ac6c019ac2"
TOMO_RELEASE_BASE="https://github.com/cbabil/tomo/releases/download"

# version_ge <a> <b>: true if dotted version a >= b (numeric per component).
version_ge() {
    local IFS=. i a=() b=()
    read -r -a a <<< "$1"; read -r -a b <<< "$2"
    for i in 0 1 2 3; do
        [ "${a[i]:-0}" -gt "${b[i]:-0}" ] && return 0
        [ "${a[i]:-0}" -lt "${b[i]:-0}" ] && return 1
    done
    return 0
}

# tomo_download <url> <dest>
# Downloads to <dest>. Returns 0 on 200, 44 on 404 (dest removed), 1 on any
# other failure (dest removed), so callers can tell "absent" from "broken".
tomo_download() {
    local url="$1" dest="$2" code
    code=$(curl -sSL --connect-timeout 10 --max-time 300 -w '%{http_code}' -o "${dest}" "${url}") \
        || code="000"
    case "${code}" in
        200) return 0 ;;
        404) rm -f "${dest}"; return 44 ;;
        *)   rm -f "${dest}"; echo "ERROR: could not download ${url} (HTTP ${code})" >&2; return 1 ;;
    esac
}

# file_sha256 <file>
# Prints the sha256 of a file (sha256sum on Linux, shasum on macOS).
file_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

# tomo_deb_url <version> <arch>
tomo_deb_url() {
    echo "${TOMO_RELEASE_BASE}/v$1/tomo_$1_$2.deb"
}

# tomo_version
# Prints the Tomo version to install (override or pinned default).
tomo_version() {
    local version="${OS_TOMO_VERSION:-${TOMO_DEFAULT_VERSION}}"
    if ! [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "ERROR: invalid OS_TOMO_VERSION '${version}' (expected x.y.z)" >&2
        return 1
    fi
    echo "${version}"
}

# tomo_expected_sha <arch>
# Prints the expected sha256 for the selected version and architecture.
# A version other than the pinned default must come with its own checksum.
tomo_expected_sha() {
    local arch="$1" suffix var default sha version
    suffix=$(echo "${arch}" | tr '[:lower:]' '[:upper:]')
    var="OS_TOMO_SHA256_${suffix}"
    default="TOMO_DEFAULT_SHA256_${suffix}"
    version=$(tomo_version) || return 1
    sha="${!var:-}"
    if [ -z "${sha}" ]; then
        if [ "${version}" != "${TOMO_DEFAULT_VERSION}" ]; then
            echo "ERROR: OS_TOMO_VERSION=${version} requires ${var}" >&2
            return 1
        fi
        sha="${!default:-}"
    fi
    if ! [[ "${sha}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: invalid ${var} '${sha}' (expected 64 lowercase hex chars)" >&2
        return 1
    fi
    echo "${sha}"
}

# fetch_tomo_deb <arch> <cache-dir>
# Prints the path of a verified Tomo .deb (last line of output).
fetch_tomo_deb() {
    local arch="$1" cache="$2" version expected dest tmp

    if [ -n "${OS_TOMO_DEB:-}" ]; then
        if [ ! -f "${OS_TOMO_DEB}" ]; then
            echo "ERROR: OS_TOMO_DEB '${OS_TOMO_DEB}' not found" >&2
            return 1
        fi
        echo "WARNING: using local Tomo package ${OS_TOMO_DEB} (checksum not verified)" >&2
        echo "${OS_TOMO_DEB}"
        return 0
    fi

    version=$(tomo_version) || return 1
    expected=$(tomo_expected_sha "${arch}") || return 1
    dest="${cache}/tomo_${version}_${arch}.deb"

    if [ -f "${dest}" ] && [ "$(file_sha256 "${dest}")" = "${expected}" ]; then
        echo "Using cached Tomo ${version} (${arch})." >&2
        echo "${dest}"
        return 0
    fi

    install -d "${cache}"
    tmp="${dest}.partial"
    if ! tomo_download "$(tomo_deb_url "${version}" "${arch}")" "${tmp}"; then
        echo "ERROR: failed to download Tomo ${version} (${arch})" >&2
        return 1
    fi
    if [ "$(file_sha256 "${tmp}")" != "${expected}" ]; then
        echo "ERROR: Tomo ${version} (${arch}) checksum mismatch" >&2
        rm -f "${tmp}"
        return 1
    fi
    if ! verify_tomo_bundle "${tmp}" "$(tomo_deb_url "${version}" "${arch}")" "${version}" "${dest}"; then
        rm -f "${tmp}" "${dest}.sigstore.json"
        return 1
    fi
    mv "${tmp}" "${dest}"
    echo "Downloaded Tomo ${version} (${arch})." >&2
    echo "${dest}"
}

# verify_tomo_bundle <deb> <deb-url> <version> <dest>
# Signed Tomo releases publish <deb>.sigstore.json; verify it against Tomo's
# release workflow at that version's tag. A release from before
# TOMO_SIGNED_SINCE may have no bundle: warn, and rely on the sha256 pin.
# Any other download failure is fatal, so a network error can't silently
# skip verification.
verify_tomo_bundle() {
    local deb="$1" url="$2" version="$3" dest="$4"
    local bundle="${dest}.sigstore.json" status=0
    tomo_download "${url}.sigstore.json" "${bundle}" || status=$?
    if [ "${status}" -eq 44 ]; then
        if version_ge "${version}" "${TOMO_SIGNED_SINCE}"; then
            echo "ERROR: Tomo ${version} must be signed (releases since ${TOMO_SIGNED_SINCE} are), but has no Sigstore bundle" >&2
            return 1
        fi
        echo "WARNING: Tomo ${version} is not signed (no Sigstore bundle); relying on the sha256 pin" >&2
        return 0
    elif [ "${status}" -ne 0 ]; then
        return 1
    fi
    sigstore_verify "${deb}" "${bundle}" "${TOMO_REPO}" "${TOMO_RELEASE_WORKFLOW}" "v${version}" || return 1
    echo "Tomo ${version} signature verified (${TOMO_REPO} ${TOMO_RELEASE_WORKFLOW}@v${version})." >&2
}
