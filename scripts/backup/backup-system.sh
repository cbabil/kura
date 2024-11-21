#!/bin/bash
set -e

BACKUP_DIR="/var/lib/stratura/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${TIMESTAMP}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# Backup system configuration
tar czf "${BACKUP_PATH}/system-config.tar.gz" /etc/stratura

# Backup container data
for container in $(docker ps -a --format '{{.Names}}'); do
    docker inspect $container > "${BACKUP_PATH}/${container}-config.json"
    if [ -d "/var/lib/stratura/volumes/${container}" ]; then
        tar czf "${BACKUP_PATH}/${container}-data.tar.gz" \
            "/var/lib/stratura/volumes/${container}"
    fi
done

# Backup certificates and keys
tar czf "${BACKUP_PATH}/certs.tar.gz" /etc/stratura/certs

# Create backup manifest
cat > "${BACKUP_PATH}/manifest.json" <<EOF
{
    "timestamp": "$(date -Iseconds)",
    "version": "$(cat /etc/stratura/version)",
    "containers": $(docker ps -a --format '{{.Names}}' | jq -R -s -c 'split("\n")[:-1]')
}
EOF

# Calculate checksums
cd "${BACKUP_PATH}"
sha256sum * > SHA256SUMS
gpg --detach-sign --armor SHA256SUMS

# Encrypt sensitive data
gpg --encrypt --recipient backup@stratura.io certs.tar.gz 