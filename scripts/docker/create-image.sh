#!/bin/bash
# scripts/docker/create-image.sh
# Create a minimized Docker rootfs tarball.
# This runs a SEPARATE mmdebstrap (not the same rootfs as RPi5/PC).
#
# Usage: create-image.sh <output-dir> <arch>
# Requires: OS_* env vars exported by build.sh

set -euo pipefail

OUTPUT_DIR="${1:?Usage: $0 <output-dir> <arch>}"
ARCH="${2:-amd64}"

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "$(dirname "$0")/../common/brand-defaults.sh"

BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
SUITE="${OS_DEBIAN_SUITE:-trixie}"
MIRROR="${OS_DEBIAN_MIRROR:-http://deb.debian.org/debian}"
VERSION="${OS_VERSION:-2.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$(cd "$(dirname "$0")/../../packages" && pwd)"
DOCKER_ROOTFS="${OS_TMP:-/tmp}/${BRAND}-docker-$$"
BUILD_SEQ="${OS_BUILD_SEQ:-0001}"

trap 'rm -rf "${DOCKER_ROOTFS}"' EXIT

echo "Creating Docker rootfs (${ARCH})..."

# ---- Bootstrap minimal rootfs ----
mmdebstrap --variant=minbase --arch="${ARCH}" --quiet \
    "${SUITE}" "${DOCKER_ROOTFS}" "${MIRROR}"

# ---- Install runtime deps (no kernel, no systemd, no Docker) ----
chroot "${DOCKER_ROOTFS}" apt-get update -qq
chroot "${DOCKER_ROOTFS}" apt-get install -y --no-install-recommends \
    jq network-manager openssh-server curl nano

# ---- Install OS packages ----
"${SCRIPT_DIR}/common/install-os-pkgs.sh" "${DOCKER_ROOTFS}" "${PKG_DIR}"

# ---- Aggressive minimization ----
rm -rf "${DOCKER_ROOTFS}/usr/share/doc"
rm -rf "${DOCKER_ROOTFS}/usr/share/man"
rm -rf "${DOCKER_ROOTFS}/usr/share/info"
rm -rf "${DOCKER_ROOTFS}/var/lib/apt/lists"/*
rm -rf "${DOCKER_ROOTFS}/var/cache/apt"/*
rm -rf "${DOCKER_ROOTFS}/var/log"/*
# Keep only C and en_US locales
find "${DOCKER_ROOTFS}/usr/share/locale" -mindepth 1 -maxdepth 1 \
    ! -name 'C' ! -name 'en_US' -exec rm -rf {} + 2>/dev/null || true

# ---- Create tarball ----
VARIANT="x86_64"
[ "${ARCH}" = "arm64" ] && VARIANT="rpi5"
TAR_NAME="${BRAND}-${VERSION}-${VARIANT}-${ARCH}-${BUILD_DATE:-$(date +%Y%m%d)}-${BUILD_SEQ}.tar"

mkdir -p "${OUTPUT_DIR}"
tar -C "${DOCKER_ROOTFS}" -cf "${OUTPUT_DIR}/${TAR_NAME}" .

echo "Docker rootfs tarball: ${OUTPUT_DIR}/${TAR_NAME}"

# ---- Import to Docker (if available) ----
if command -v docker >/dev/null 2>&1; then
    docker import "${OUTPUT_DIR}/${TAR_NAME}" "${BRAND}:${VERSION}-${ARCH}-${BUILD_SEQ}"
    docker tag "${BRAND}:${VERSION}-${ARCH}-${BUILD_SEQ}" "${BRAND}:latest-${ARCH}"
    echo "Docker image tagged: ${BRAND}:latest-${ARCH}"
fi
