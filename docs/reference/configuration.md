# Configuration Reference

## Local Configuration (`conf/local.conf`)

### Machine Configuration
- `MACHINE`: Set to `raspberrypi5` for Raspberry Pi 5 support.

### Distribution Configuration
- `DISTRO`: Set to `straturaOS` for custom distribution.

### Package Management
- `PACKAGE_CLASSES`: Use `package_ipk` for package management.

### Features
- `DISTRO_FEATURES`: Append `systemd`, `virtualization`, `bluetooth`, `wifi`, `rauc`, `docker`.

### Image Configuration
- `IMAGE_INSTALL`: Append necessary packages like `docker-ce`, `networkmanager`, `stratura-supervisor`.

### GPU and DRM
- `GPU_MEM`: Set to `256` for GPU memory allocation.
- `ENABLE_DRM`: Set to `1` to enable Direct Rendering Manager.

### Partition Sizes
- `STRATURA_BOOTLOADER_PARTITION_SIZE`: Set to `40960` for bootloader partition.
- `STRATURA_STATE_PARTITION_SIZE`: Set to `20480` for state partition.
- `STRATURA_DATA_PARTITION_SIZE`: Set to `204800` for data partition.

## Network Configuration

### NetworkManager
- Configure `/etc/NetworkManager/conf.d/00-stratura-network.conf` for network settings.

## Update Configuration

### RAUC
- Configure `/etc/rauc/system.conf` for update slots and handlers.

## Security Configuration

### SELinux and AppArmor
- Configure policies in `/etc/stratura/selinux` and `/etc/apparmor.d/stratura`.

### Firewall
- Configure firewall rules in `/etc/stratura/firewall.conf`.

## Container Configuration

### Docker
- Configure `/etc/docker/daemon.json` for Docker settings.

## Monitoring and Logging

### Prometheus
- Configure Prometheus metrics in `/etc/stratura/metrics-config.json`.

### Logging
- Configure logging settings in `/etc/stratura/logging.conf`. 