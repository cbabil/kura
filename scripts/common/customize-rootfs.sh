#!/bin/bash
# scripts/common/customize-rootfs.sh
# Shared rootfs customization (runs outside chroot, operates on rootfs directory).
# Adapted from buildroot-external/board/straturaos/post-build.sh
#
# Usage: customize-rootfs.sh <rootfs-dir>
# Requires: STRATURAOS_* env vars exported by build.sh

set -euo pipefail

ROOTFS="${1:?Usage: $0 <rootfs-dir>}"

OS_NAME="${STRATURAOS_NAME:-StraturaOS}"
HOSTNAME="${STRATURAOS_HOSTNAME:-straturaos}"
export ROOT_PASSWD="${STRATURAOS_ROOT_PASSWD:-stratura}"
VERSION="${STRATURAOS_VERSION:-2.0}"
DHCP_IFACE="${STRATURAOS_DHCP_INTERFACE:-eth0}"

echo "Customizing rootfs at ${ROOTFS}..."

# ---- Directory structure ----
install -d -m 0755 "${ROOTFS}/var/lib/stratura"
install -d -m 0755 "${ROOTFS}/var/lib/stratura/volumes"
install -d -m 0755 "${ROOTFS}/var/lib/stratura-supervisor"
install -d -m 0755 "${ROOTFS}/var/log/stratura"
install -d -m 0700 "${ROOTFS}/etc/stratura/certs"
install -d -m 0755 "${ROOTFS}/mnt/data"

# ---- Hostname ----
echo "${HOSTNAME}" > "${ROOTFS}/etc/hostname"
cat > "${ROOTFS}/etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	${HOSTNAME}
::1		localhost ip6-localhost ip6-loopback
EOF

# ---- Permissions ----
chmod 700 "${ROOTFS}/etc/stratura"
chmod 755 "${ROOTFS}/var/lib/stratura"
chmod 755 "${ROOTFS}/var/log/stratura"

# ---- Python environment ----
install -d "${ROOTFS}/etc/profile.d"
cat > "${ROOTFS}/etc/profile.d/stratura.sh" <<'EOF'
export PYTHONPATH=/usr/lib/stratura
export STRATURA_CONFIG=/etc/stratura/config.json
EOF

# ---- Enable systemd services ----
# multi-user.target
for svc in stratura-supervisor stratura-config; do
    install -d "${ROOTFS}/etc/systemd/system/multi-user.target.wants"
    ln -sf "/usr/lib/systemd/system/${svc}.service" \
        "${ROOTFS}/etc/systemd/system/multi-user.target.wants/${svc}.service"
done

# sysinit.target (security runs early)
install -d "${ROOTFS}/etc/systemd/system/sysinit.target.wants"
ln -sf "/usr/lib/systemd/system/stratura-security.service" \
    "${ROOTFS}/etc/systemd/system/sysinit.target.wants/stratura-security.service"

# ---- Patch config.json with env values ----
if [ -f "${ROOTFS}/etc/stratura/config.json" ]; then
    sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"${VERSION}\"/" \
        "${ROOTFS}/etc/stratura/config.json"
    sed -i "s/\"hostname\": \"[^\"]*\"/\"hostname\": \"${HOSTNAME}\"/" \
        "${ROOTFS}/etc/stratura/config.json"
    sed -i "s/\"interface\": \"[^\"]*\"/\"interface\": \"${DHCP_IFACE}\"/" \
        "${ROOTFS}/etc/stratura/config.json"
fi

# ---- ANSI color definitions (IBM green phosphor) ----
ESC=$'\033'
B="${ESC}[1;32m"    # bright green
G="${ESC}[0;32m"    # normal green
R="${ESC}[0m"       # reset

# ---- Generate colored /etc/issue (pre-login banner) ----
# agetty passes raw ANSI bytes through; \r \m \l are agetty escapes
cat > "${ROOTFS}/etc/issue" <<ISSUEEOF

${B}  ███████ ████████ ██████   █████  ████████ ██    ██ ██████   █████
  ██         ██    ██   ██ ██   ██    ██    ██    ██ ██   ██ ██   ██
  ███████    ██    ██████  ███████    ██    ██    ██ ██████  ███████
       ██    ██    ██   ██ ██   ██    ██    ██    ██ ██   ██ ██   ██
  ███████    ██    ██   ██ ██   ██    ██     ██████  ██   ██ ██   ██${R}

${B}  ${OS_NAME} v${VERSION}${G}  |  Kernel \r on \m${R}

${G}  [*] Container Runtime ............. Docker
  [*] Supervisor .................... Active
  [*] Security Module ............... Enabled
  [*] Network Manager ............... Online${R}

${G}  Console: \l${R}

ISSUEEOF

# ---- Generate colored /etc/motd (post-login banner) ----
cat > "${ROOTFS}/etc/motd" <<MOTDEOF
${G}  Type 'systemctl status' for service details.${R}
MOTDEOF

# ---- Set root password ----
# Uses chpasswd inside chroot (called by build.sh after mounting /proc etc.)
# build.sh will run: chroot ${ROOTFS} sh -c "echo 'root:${ROOT_PASSWD}' | chpasswd"

# ---- Locale (C + en_US) ----
if [ -f "${ROOTFS}/etc/locale.gen" ]; then
    sed -i 's/^# en_US.UTF-8/en_US.UTF-8/' "${ROOTFS}/etc/locale.gen"
fi

# ---- Clean apt cache ----
rm -rf "${ROOTFS}/var/cache/apt/archives"/*.deb
rm -rf "${ROOTFS}/var/lib/apt/lists"/*

echo "Common rootfs customization complete."
