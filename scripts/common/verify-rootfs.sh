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
usr/bin/${b}-config
usr/bin/${b}-security
usr/lib/systemd/system/${b}-config.service
usr/lib/systemd/system/${b}-security.service
etc/${b}/security/hardening.json
usr/lib/${b}/firstboot.sh
usr/lib/${b}/kanji.sh
usr/lib/${b}/updates.sh
usr/lib/${b}/migrations/001-storage-status.sh
usr/lib/${b}/migrations/002-console-font.sh
usr/lib/${b}/pkg-hooks.sh
usr/lib/${b}/avahi-daemon.conf
usr/lib/systemd/system/avahi-daemon.service.d/10-${b}.conf
usr/lib/${b}/release
var/lib/dpkg/info/${b}.list
usr/lib/${b}/firstboot-setup.sh
usr/lib/${b}/firstboot-setup-check.sh
usr/lib/${b}/firstboot-disk.sh
usr/lib/${b}/firstboot-password.sh
usr/lib/${b}/firstboot-storage.sh
usr/lib/${b}/firstboot-storage-check.sh
usr/sbin/lvcreate
usr/sbin/sfdisk
usr/lib/systemd/system/${b}-firstboot.service
usr/lib/systemd/system/${b}-storage.service
usr/lib/systemd/system/${b}-ssh-keygen.service
usr/bin/unattended-upgrade
etc/apt/apt.conf.d/20auto-upgrades
usr/lib/systemd/systemd-timesyncd
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
${w}/multi-user.target.wants/${b}-config.service
${w}/multi-user.target.wants/${b}-firstboot.service
${w}/local-fs.target.wants/${b}-storage.service
${w}/multi-user.target.wants/${b}-ssh-keygen.service
${w}/sysinit.target.wants/${b}-security.service
${w}/network-online.target.wants/NetworkManager-wait-online.service
${w}/timers.target.wants/apt-daily.timer
${w}/timers.target.wants/apt-daily-upgrade.timer
${w}/sysinit.target.wants/systemd-timesyncd.service
EOF
}

# rootfs_forbidden_paths <brand>
# Components removed from Kura (ADR-013 Tomo, ADR-014 the supervisor) that
# must not come back into an image.
rootfs_forbidden_paths() {
    local b="$1"
    cat <<EOF
opt/tomo
usr/local/bin/bun
opt/${b}-supervisor
usr/lib/systemd/system/${b}-supervisor.service
EOF
}

# rootfs_unowned_paths <rootfs>: "<uid>:<gid> /<path>" for each path on the
# rootfs's filesystem whose owner has no account in its /etc/passwd or whose
# group has no entry in its /etc/group: the image's `find / -xdev \( -nouser
# -o -nogroup \)`, judged by the image's accounts, not the build host's. A
# file left with the build user's ID (1001 on CI) would belong to whichever
# account later gets that ID.
rootfs_unowned_paths() {
    local root="${1%/}" # "" for "/" itself
    # perl's lstat reads owners the same way on Linux and macOS (stat's
    # options differ); find -print0 keeps names with spaces or newlines whole
    find "${root:-/}" -xdev -print0 | perl -0ne '
        BEGIN {
            ($root) = @ARGV; @ARGV = ();
            for (["passwd", \%uid], ["group", \%gid]) {
                my ($file, $ids) = @$_;
                open(my $fh, "<", "$root/etc/$file") or next;
                local $/ = "\n";
                while (<$fh>) { my @f = split /:/; $ids->{$f[2]} = 1 if defined $f[2] }
            }
        }
        chomp;
        my @st = lstat($_) or next;
        next if $uid{$st[4]} && $gid{$st[5]};
        my $path = substr($_, length $root);
        print "$st[4]:$st[5] ", ($path eq "" ? "/" : $path), "\n";
    ' "${root}"
}

# verify_owners <rootfs>: prints the paths rootfs_unowned_paths finds (the
# first 20) and returns 1 if there is any
verify_owners() {
    local unowned
    unowned=$(rootfs_unowned_paths "$1")
    [ -n "${unowned}" ] || return 0
    echo "  $(wc -l <<< "${unowned}" | tr -d ' ') paths have an owner or group with no account (uid:gid path):" >&2
    head -n 20 <<< "${unowned}" | sed 's/^/    /' >&2
    return 1
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
    while read -r f; do
        [ ! -e "${rootfs}/${f}" ] || { echo "  UNEXPECTED: /${f}" >&2; status=1; }
    done < <(rootfs_forbidden_paths "${brand}")

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
    # Every package must be signature-checked
    if grep -rqiE '\[[^]]*trusted=yes|^Trusted:[[:space:]]*yes' \
            "${rootfs}/etc/apt/sources.list" "${rootfs}/etc/apt/sources.list.d" 2>/dev/null; then
        echo "  an APT source skips signature checks (trusted=yes)" >&2
        status=1
    fi
    # Every file belongs to an account of the image (root, mostly)
    verify_owners "${rootfs}" || status=1
    if ! login_user_has_sudo "${rootfs}"; then
        echo "  the login user is not in the sudo group (no way to root)" >&2
        status=1
    fi
    return "${status}"
}
