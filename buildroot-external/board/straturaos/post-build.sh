#!/bin/bash
# StraturaOS post-build script
# Runs after rootfs is created but before image is generated

set -e

TARGET_DIR=$1

echo "StraturaOS: Running post-build configuration..."

# Create required directories
mkdir -p ${TARGET_DIR}/var/lib/stratura
mkdir -p ${TARGET_DIR}/var/log/stratura
mkdir -p ${TARGET_DIR}/etc/stratura/certs
mkdir -p ${TARGET_DIR}/mnt/data

# Enable StraturaOS services
if [ -d ${TARGET_DIR}/usr/lib/systemd/system ]; then
    mkdir -p ${TARGET_DIR}/etc/systemd/system/multi-user.target.wants

    # Enable services
    for service in stratura-supervisor stratura-config; do
        if [ -f ${TARGET_DIR}/usr/lib/systemd/system/${service}.service ]; then
            ln -sf /usr/lib/systemd/system/${service}.service \
                ${TARGET_DIR}/etc/systemd/system/multi-user.target.wants/${service}.service
            echo "Enabled ${service}.service"
        fi
    done

    # Enable security service at boot
    mkdir -p ${TARGET_DIR}/etc/systemd/system/sysinit.target.wants
    if [ -f ${TARGET_DIR}/usr/lib/systemd/system/stratura-security.service ]; then
        ln -sf /usr/lib/systemd/system/stratura-security.service \
            ${TARGET_DIR}/etc/systemd/system/sysinit.target.wants/stratura-security.service
        echo "Enabled stratura-security.service"
    fi
fi

# Set hostname
echo "${STRATURAOS_HOSTNAME:-straturaos}" > ${TARGET_DIR}/etc/hostname

# Configure hosts file
cat > ${TARGET_DIR}/etc/hosts << EOF
127.0.0.1       localhost
127.0.1.1       ${STRATURAOS_HOSTNAME:-straturaos}
::1             localhost ip6-localhost ip6-loopback
EOF

# Set permissions
chmod 700 ${TARGET_DIR}/etc/stratura
chmod 755 ${TARGET_DIR}/var/lib/stratura
chmod 755 ${TARGET_DIR}/var/log/stratura

# Create Stratura environment configuration
mkdir -p ${TARGET_DIR}/etc/profile.d
cat > ${TARGET_DIR}/etc/profile.d/stratura.sh << 'EOF'
export STRATURA_CONFIG=/etc/stratura/config.json
EOF

# Patch config.json with env values
CONF="${TARGET_DIR}/etc/stratura/config.json"
if [ -f "${CONF}" ]; then
    sed -i "s|\"version\": \"[^\"]*\"|\"version\": \"${STRATURAOS_VERSION:-1.0}\"|" "${CONF}"
    sed -i "s|\"hostname\": \"[^\"]*\"|\"hostname\": \"${STRATURAOS_HOSTNAME:-straturaos}\"|" "${CONF}"
    sed -i "s|\"interface\": \"[^\"]*\"|\"interface\": \"${STRATURAOS_DHCP_INTERFACE:-eth0}\"|" "${CONF}"
fi

echo "StraturaOS: Post-build configuration complete"
