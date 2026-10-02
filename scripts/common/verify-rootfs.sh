#!/bin/bash
# scripts/common/verify-rootfs.sh
# Fail-fast checks run on every image rootfs before the artifact is created.
# Source this file; it defines functions only.

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/passwords.sh"

# rootfs_required_files <brand>
# Files every image must contain (paths relative to the rootfs).
rootfs_required_files() {
    local b="$1"
    cat <<EOF
usr/bin/docker
usr/bin/dockerd
usr/bin/containerd
usr/libexec/docker/cli-plugins/docker-compose
usr/lib/systemd/system/docker.service
usr/lib/systemd/system/containerd.service
usr/bin/node
opt/tomo/dist/index.js
opt/tomo/public/index.html
etc/systemd/system/tomod.service
usr/share/${b}/images/traefik.tar
usr/local/bin/bun
usr/bin/${b}-config
usr/bin/${b}-security
usr/lib/systemd/system/${b}-supervisor.service
usr/lib/systemd/system/${b}-config.service
usr/lib/systemd/system/${b}-security.service
opt/${b}-supervisor/src/index.js
opt/${b}-supervisor/node_modules
etc/${b}/supervisor-config.json
etc/${b}/security/hardening.json
usr/lib/${b}/firstboot.sh
usr/lib/systemd/system/${b}-firstboot.service
usr/lib/systemd/system/${b}-ssh-keygen.service
EOF
}

# rootfs_required_links <brand>
# systemd enable links every image must contain. Their targets are absolute
# paths into the image, so they are checked with -L, not followed.
rootfs_required_links() {
    local b="$1" w="etc/systemd/system"
    cat <<EOF
${w}/multi-user.target.wants/docker.service
${w}/multi-user.target.wants/containerd.service
${w}/multi-user.target.wants/tomod.service
${w}/multi-user.target.wants/${b}-supervisor.service
${w}/multi-user.target.wants/${b}-config.service
${w}/multi-user.target.wants/${b}-firstboot.service
${w}/multi-user.target.wants/${b}-ssh-keygen.service
${w}/sysinit.target.wants/${b}-security.service
${w}/network-online.target.wants/NetworkManager-wait-online.service
EOF
}

# verify_rootfs <rootfs> <brand>
# Prints every problem found and returns 1 if there is any.
verify_rootfs() {
    local rootfs="$1" brand="$2" status=0 f
    while read -r f; do
        [ -e "${rootfs}/${f}" ] || { echo "  MISSING: /${f}" >&2; status=1; }
    done < <(rootfs_required_files "${brand}")
    while read -r f; do
        [ -L "${rootfs}/${f}" ] || { echo "  MISSING symlink: /${f}" >&2; status=1; }
    done < <(rootfs_required_links "${brand}")

    # Device identity must be generated on the device, never baked in
    if compgen -G "${rootfs}/etc/ssh/ssh_host_*" >/dev/null; then
        echo "  SSH host keys baked into the image" >&2
        status=1
    fi
    if [ -s "${rootfs}/etc/machine-id" ]; then
        echo "  /etc/machine-id is not empty" >&2
        status=1
    fi
    # Nor may a public password survive the first login
    if ! login_password_expired "${rootfs}"; then
        echo "  the login user's password is not expired" >&2
        status=1
    fi
    if ! root_password_locked "${rootfs}"; then
        echo "  root's password is not locked" >&2
        status=1
    fi
    if ! login_user_has_sudo "${rootfs}"; then
        echo "  the login user is not in the sudo group (no way to root)" >&2
        status=1
    fi
    return "${status}"
}
