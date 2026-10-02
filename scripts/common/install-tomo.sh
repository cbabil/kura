#!/bin/bash
# scripts/common/install-tomo.sh
# Installs the Tomo release .deb into the image rootfs (from a chroot).
#
# Tomo's postinst calls systemctl directly (daemon-reload, start) under
# `set -e`. Inside a chroot there is no running systemd, so those calls fail
# and abort the install; policy-rc.d only covers invoke-rc.d. For the duration
# of the install, /usr/bin/systemctl is diverted to a no-op stub and tomod is
# enabled explicitly afterwards.
#
# Must run while build.sh's policy-rc.d is in place and apt lists are present.
# Source this file; it defines functions only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/systemd-units.sh"

TOMO_SYSTEMCTL_DIVERT="/usr/bin/systemctl.kura-real"
TOMO_UNIT="/etc/systemd/system/tomod.service"
TOMO_JWT="/opt/tomo/data/secrets/jwt"
TOMO_TRAEFIK_JS="/opt/tomo/dist/traefik-proxy.js"

# _tomo_stub_systemctl <rootfs>
_tomo_stub_systemctl() {
    chroot "$1" dpkg-divert --local --rename \
        --divert "${TOMO_SYSTEMCTL_DIVERT}" --add /usr/bin/systemctl >/dev/null
    printf '#!/bin/sh\n# Kura build stub: no systemd in the chroot\nexit 0\n' \
        > "$1/usr/bin/systemctl"
    chmod 0755 "$1/usr/bin/systemctl"
}

# _tomo_restore_systemctl <rootfs>
_tomo_restore_systemctl() {
    rm -f "$1/usr/bin/systemctl"
    chroot "$1" dpkg-divert --local --rename \
        --divert "${TOMO_SYSTEMCTL_DIVERT}" --remove /usr/bin/systemctl >/dev/null
}

# install_tomo <rootfs> <deb>
# Installs Tomo, enables tomod at boot and removes the JWT secret the
# package generated, so every device creates its own on first start.
install_tomo() {
    local rootfs="$1" deb="$2" status=0

    if [ ! -f "${deb}" ]; then
        echo "ERROR: Tomo package ${deb} not found" >&2
        return 1
    fi

    install -m 0644 "${deb}" "${rootfs}/tmp/tomo.deb"
    _tomo_stub_systemctl "${rootfs}"
    chroot "${rootfs}" apt-get install -y -qq --no-install-recommends /tmp/tomo.deb \
        || status=$?
    _tomo_restore_systemctl "${rootfs}"
    rm -f "${rootfs}/tmp/tomo.deb"

    if [ "${status}" -ne 0 ]; then
        echo "ERROR: failed to install Tomo (apt-get exit ${status})" >&2
        return "${status}"
    fi
    if [ ! -f "${rootfs}${TOMO_UNIT}" ]; then
        echo "ERROR: Tomo package did not install ${TOMO_UNIT}" >&2
        return 1
    fi

    enable_unit "${rootfs}" multi-user.target "${TOMO_UNIT}"
    rm -f "${rootfs}${TOMO_JWT}"
    echo "Tomo installed."
}

# tomo_traefik_image <rootfs>
# Prints the Traefik image the installed tomod runs (e.g. traefik:v3.3),
# read from Tomo's own code so the offline copy always matches the release.
tomo_traefik_image() {
    local file="$1${TOMO_TRAEFIK_JS}" version
    if [ ! -f "${file}" ]; then
        echo "ERROR: ${TOMO_TRAEFIK_JS} not found in rootfs" >&2
        return 1
    fi
    version=$(sed -n 's/^const TRAEFIK_VERSION = "\(v[0-9][0-9.]*\)";.*/\1/p' "${file}" | head -1)
    if [ -z "${version}" ]; then
        echo "ERROR: TRAEFIK_VERSION not found in ${TOMO_TRAEFIK_JS}" >&2
        return 1
    fi
    echo "traefik:${version}"
}

# save_tomo_images <rootfs> <brand> <arch> <cache-dir>
# Saves the container images tomod needs at first start into
# /usr/share/<brand>/images/, so first boot works without internet
# (kura-firstboot loads them). Uses skopeo on the build host: no Docker
# daemon needed, and it can fetch another architecture's image.
save_tomo_images() {
    local rootfs="$1" brand="$2" arch="$3" cache="$4" image archive dest
    image=$(tomo_traefik_image "${rootfs}") || return 1
    archive="${cache}/${image/:/-}-${arch}.tar"
    dest="${rootfs}/usr/share/${brand}/images"

    if [ ! -f "${archive}" ]; then
        install -d "${cache}"
        if ! skopeo copy --quiet --override-os linux --override-arch "${arch}" \
                "docker://docker.io/library/${image}" \
                "docker-archive:${archive}.partial:${image}"; then
            echo "ERROR: failed to save ${image} (${arch})" >&2
            rm -f "${archive}.partial"
            return 1
        fi
        mv "${archive}.partial" "${archive}"
    fi
    install -d "${dest}"
    install -m 0644 "${archive}" "${dest}/traefik.tar"
    echo "Saved ${image} (${arch}) for offline first boot."
}
