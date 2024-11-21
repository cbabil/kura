# straturaOS Architecture Overview

## Core Components

### 1. Base System
- Yocto-based Linux distribution
- Systemd init system
- RAUC update framework
- Docker container runtime

### 2. System Services
- **Supervisor**: Container and system management
- **Update Client**: OTA update handling
- **Network Manager**: Network configuration and failover
- **Security Manager**: System hardening and security policies

### 3. State Management
- A/B partition scheme for failsafe updates
- Persistent state partition
- Container data volumes

## System Layout

### Partition Structure
```
/dev/mmcblk0p1 - Boot partition (FAT32)
/dev/mmcblk0p2 - Root A (ext4)
/dev/mmcblk0p3 - Root B (ext4)
/dev/mmcblk0p4 - Boot B (FAT32)
/dev/mmcblk0p5 - State (ext4)
/dev/mmcblk0p6 - Data (ext4)
```

### Directory Structure
```
/etc/stratura/          - System configuration
/var/lib/stratura/      - System state and data
/var/lib/docker/        - Container storage
/mnt/data/             - Persistent data storage
```

## Security Architecture

### 1. Boot Security
- Secure boot with TPM integration
- Bootloader verification
- Kernel and initramfs signing

### 2. Runtime Security
- SELinux policies
- AppArmor profiles
- Seccomp filters
- Container isolation

### 3. Update Security
- Signed updates
- Rollback protection
- Failsafe recovery

## Network Architecture

### 1. Connectivity
- Primary connection (Ethernet/WiFi)
- Failover support
- VPN integration

### 2. Management Interface
- REST API (port 48484)
- SSL/TLS encryption
- Token-based authentication

## Container Architecture

### 1. Runtime
- Docker with containerd
- OCI-compliant
- Resource constraints

### 2. Storage
- OverlayFS
- Volume management
- Persistent data

### 3. Networking
- Bridge networking
- Host networking option
- Container isolation