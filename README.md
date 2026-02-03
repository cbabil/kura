# StraturaOS

StraturaOS is a custom operating system designed for the Raspberry Pi 5, built on Buildroot. It offers robust container support, over-the-air (OTA) updates, and advanced device management capabilities, making it ideal for IoT and edge computing applications.

## Features

- **Buildroot-based**: Lightweight and customizable Linux distribution
- **Container Support**: Integrated Docker runtime for containerized applications
- **OTA Updates**: Secure and reliable over-the-air update mechanism using RAUC
- **Advanced Security**: Security hardening and monitoring tools
- **Network Management**: Flexible network configuration with NetworkManager
- **Device Management**: Comprehensive device monitoring and management tools

## Quick Start

### Prerequisites

- Linux build machine (Debian/Ubuntu recommended)
- At least 8GB RAM, 50GB free disk space
- Required packages:
  ```bash
  sudo apt-get install -y build-essential libncurses5-dev git wget \
      cpio unzip rsync bc libssl-dev
  ```

### Build Commands

```bash
# Clone the repository
git clone <repo-url> StraturaOS
cd StraturaOS

# Initial setup (clones Buildroot)
./build.sh setup

# Configure (optional - loads defconfig)
./build.sh config

# Build the image
./build.sh build

# Package with dated filename + create rootfs.tar
./build.sh package

# Create Docker image
./build.sh docker

# Full release (build + package + docker)
./build.sh release
```

### Build Script Commands

| Command | Description |
|---------|-------------|
| `setup` | Clone Buildroot and setup environment |
| `config` | Load StraturaOS defconfig |
| `menuconfig` | Interactive configuration menu |
| `build` | Build the SD card image |
| `package` | Create dated sdcard.img and rootfs.tar |
| `docker` | Create Docker image from rootfs |
| `iso` | Create bootable ISO (cloud/x86_64 only) |
| `export` | Package + docker + iso (no rebuild) |
| `release` | Build + package + docker + iso (full release) |
| `clean` | Clean build directory |
| `cleanup` | Remove old artifacts (keeps only latest) |
| `distclean` | Full clean (reset everything) |
| `install` | Install 'straturaos' command globally |
| `uninstall` | Remove global 'straturaos' command |

### Build Targets

**Raspberry Pi 5 (default):**
```bash
./build.sh config rpi5
./build.sh build
```

**Cloud/VM (Proxmox, KVM, QEMU):**
```bash
./build.sh config cloud
./build.sh build
```

### Output Files

Release files are organized by version in `release/{version}/`:

```
release/
└── 1.0/
    ├── arm64/                    # SD card images for Raspberry Pi
    │   ├── straturaos-1.0-rpi5-arm64-YYYYMMDD-HHMM.img
    │   ├── straturaos-1.0-rpi5-arm64-YYYYMMDD-HHMM.img.sign
    │   ├── SHA512SUMS
    │   └── SHA512SUMS.sign
    ├── amd64/                    # Cloud images for Proxmox/KVM
    │   ├── straturaos-1.0-genericcloud-amd64-YYYYMMDD-HHMM.qcow2
    │   ├── straturaos-1.0-genericcloud-amd64-YYYYMMDD-HHMM.qcow2.sign
    │   ├── SHA512SUMS
    │   └── SHA512SUMS.sign
    ├── docker/                   # Docker tarballs
    │   ├── straturaos-1.0-*-YYYYMMDD-HHMM.tar
    │   ├── straturaos-1.0-*-YYYYMMDD-HHMM.tar.sign
    │   ├── SHA512SUMS
    │   └── SHA512SUMS.sign
    └── iso/                      # Bootable ISOs for testing
        ├── straturaos-1.0-genericcloud-amd64-YYYYMMDD-HHMM.iso
        ├── straturaos-1.0-genericcloud-amd64-YYYYMMDD-HHMM.iso.sign
        ├── SHA512SUMS
        └── SHA512SUMS.sign
```

**Naming convention:** `straturaos-{version}-{variant}-{arch}-{date}-{time}.{format}`

**File types:**
- `.img` - Raw disk image (for SD card flashing)
- `.qcow2` - QEMU/Proxmox disk image
- `.iso` - Bootable ISO image (for VM testing)
- `.tar` - Root filesystem tarball (for Docker import)
- `.sign` - GPG signature
- `SHA512SUMS` - Checksums for all files

### Verify Downloads

```bash
# Verify checksum
cd release/1.0/arm64/
sha512sum -c SHA512SUMS

# Verify GPG signature (if signed)
gpg --verify SHA512SUMS.sign SHA512SUMS
```

### Flashing to SD Card (RPi 5)

```bash
sudo dd if=release/1.0/arm64/straturaos-1.0-rpi5-arm64-YYYYMMDD-HHMM.img of=/dev/sdX bs=4M status=progress
sync
```

### Deploy to Proxmox (Cloud Image)

1. Upload the QCOW2 image to Proxmox:
   ```bash
   scp release/1.0/amd64/straturaos-1.0-genericcloud-amd64-*.qcow2 root@proxmox:/var/lib/vz/images/
   ```

2. Create a VM and import the disk:
   ```bash
   qm create 100 --name straturaos --memory 2048 --cores 2 --net0 virtio,bridge=vmbr0
   qm importdisk 100 /var/lib/vz/images/straturaos-1.0-genericcloud-amd64-*.qcow2 local-lvm
   qm set 100 --scsi0 local-lvm:vm-100-disk-0
   qm set 100 --boot c --bootdisk scsi0
   qm set 100 --serial0 socket --vga serial0
   qm start 100
   ```

3. Or use the Proxmox web UI to create VM and attach the disk.

### Testing with ISO (VirtualBox, VMware, QEMU)

Boot from the ISO for quick testing:

```bash
# QEMU
qemu-system-x86_64 -cdrom release/1.0/iso/straturaos-1.0-genericcloud-amd64-*.iso \
    -m 2048 -enable-kvm -serial stdio

# VirtualBox - Create new VM and attach ISO as optical drive
# VMware - Create new VM and attach ISO as CD/DVD
```

### Running in Docker

If built on another machine, import the tarball first:

```bash
docker import release/1.0/docker/straturaos-1.0-rpi5-arm64-YYYYMMDD-HHMM.tar straturaos:1.0
docker tag straturaos:1.0 straturaos:latest
```

Then run:

```bash
docker run -it straturaos:latest /bin/bash
```

### Global Installation

Install the `straturaos` command to use it from anywhere:

```bash
./build.sh install
```

Then run from any directory:

```bash
straturaos build
straturaos export
straturaos release
```

To remove:

```bash
straturaos uninstall
```

## Project Structure

```
StraturaOS/
├── build.sh                    # Main build script
├── buildroot-external/         # Buildroot external tree
│   ├── configs/                # Defconfig files
│   │   └── straturaos_defconfig
│   ├── package/                # Custom packages
│   │   ├── stratura-api/
│   │   ├── stratura-config/
│   │   ├── stratura-monitor/
│   │   ├── stratura-security/
│   │   ├── stratura-supervisor/
│   │   └── stratura-updater/
│   └── board/straturaos/       # Board-specific files
│       ├── overlay/            # Root filesystem overlay
│       ├── post-build.sh
│       ├── post-image.sh
│       └── genimage.cfg
└── docs/                       # Documentation
```

## Documentation

- **[Architecture Overview](docs/architecture/overview.md)**: Core components and architecture
- **[Security Architecture](docs/architecture/security.md)**: Security features and configurations
- **[Development Guide](docs/development/building.md)**: Development environment setup
- **[Configuration Reference](docs/reference/configuration.md)**: Configuration options
- **[API Documentation](docs/reference/api.md)**: API endpoints for device management
- **[Troubleshooting Guide](docs/reference/troubleshooting.md)**: Common issues and solutions

## Contributing

We welcome contributions to StraturaOS! Please see our [Contributing Guide](docs/contributing.md) for more information.

## License

StraturaOS is licensed under the GNU License. See the [LICENSE](LICENSE) file for details.
