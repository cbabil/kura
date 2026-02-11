#!/bin/bash
# scripts/docker/create-image.sh
# Create a minimized Docker rootfs tarball.
# This runs a SEPARATE mmdebstrap (not the same rootfs as RPi5/ISO).
#
# Usage: create-image.sh <output-dir> <arch>
# Requires: STRATURAOS_* env vars exported by build.sh

set -euo pipefail

OUTPUT_DIR="${1:?Usage: $0 <output-dir> <arch>}"
ARCH="${2:-amd64}"

SUITE="${STRATURAOS_DEBIAN_SUITE:-trixie}"
MIRROR="${STRATURAOS_DEBIAN_MIRROR:-http://deb.debian.org/debian}"
VERSION="${STRATURAOS_VERSION:-2.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$(cd "$(dirname "$0")/../../packages" && pwd)"
DOCKER_ROOTFS="${STRATURAOS_TMP:-/tmp}/straturaos-docker-$$"
BUILD_SEQ="${STRATURAOS_BUILD_SEQ:-0001}"

trap 'rm -rf "${DOCKER_ROOTFS}"' EXIT

echo "Creating Docker rootfs (${ARCH})..."

# ---- Bootstrap minimal rootfs ----
mmdebstrap --variant=minbase --arch="${ARCH}" \
    "${SUITE}" "${DOCKER_ROOTFS}" "${MIRROR}"

# ---- Install Python deps only (no kernel, no systemd, no Docker) ----
chroot "${DOCKER_ROOTFS}" apt-get update -qq
chroot "${DOCKER_ROOTFS}" apt-get install -y --no-install-recommends \
    python3 python3-jinja2 python3-yaml python3-requests python3-setuptools \
    network-manager openssh-server curl nano

# ---- Install Stratura packages ----
"${SCRIPT_DIR}/common/install-stratura-pkgs.sh" "${DOCKER_ROOTFS}" "${PKG_DIR}"

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
TAR_NAME="straturaos-${VERSION}-${VARIANT}-${ARCH}-${BUILD_DATE:-$(date +%Y%m%d)}-${BUILD_SEQ}.tar"

mkdir -p "${OUTPUT_DIR}"
tar -C "${DOCKER_ROOTFS}" -cf "${OUTPUT_DIR}/${TAR_NAME}" .

echo "Docker rootfs tarball: ${OUTPUT_DIR}/${TAR_NAME}"

# ---- Import to Docker (if available) ----
if command -v docker >/dev/null 2>&1; then
    docker import "${OUTPUT_DIR}/${TAR_NAME}" "straturaos:${VERSION}-${ARCH}-${BUILD_SEQ}"
    docker tag "straturaos:${VERSION}-${ARCH}-${BUILD_SEQ}" "straturaos:latest-${ARCH}"
    echo "Docker image tagged: straturaos:latest-${ARCH}"
fi
