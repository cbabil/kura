# StraturaOS

StraturaOS is a custom operating system built on Buildroot for Raspberry Pi 5 and x86_64 VMs. It offers container support, device management, and security hardening for IoT and edge computing applications.

## Features

- **Buildroot-based**: Lightweight and customizable Linux distribution
- **Container Support**: Integrated Docker runtime
- **Security**: Security hardening and monitoring tools
- **Network Management**: NetworkManager for flexible configuration

## Quick Start

### 1. Set up Build VM

Create a Debian/Ubuntu VM with:
- 2+ CPU cores
- 4GB+ RAM (8GB recommended)

**Disk Partitioning:**

| Mount | Minimal | Recommended | Purpose |
|-------|---------|-------------|---------|
| `/` | 10GB | 15GB | OS, tools, packages |
| `/tmp` | 5GB | 10GB | Temporary build files |
| `/home` | 30GB | 75GB | Buildroot, source, builds, releases |
| `swap` | 4GB | 8GB | Swap (helps parallel builds) |
| **Total** | **50GB** | **108GB** | |

**Note:** Set `STRATURAOS_TMP` environment variable to use a different temp directory if needed (default: `/home/straturaos/tmp`).

### 2. Install StraturaOS

```bash
# Create project directory
mkdir -p /home/straturaos
cd /home/straturaos

# Clone repository (or copy via SCP)
git clone <repo-url> .

# Setup (installs dependencies + clones Buildroot)
./build.sh setup

# Install global command
./build.sh install
```

### 3. Build

```bash
straturaos build           # Build all targets (clean build)
straturaos build iso       # Build x86_64 only (incremental)
straturaos build rpi5      # Build RPi5 only (incremental)
```

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Install dependencies and clone Buildroot |
| `build [target]` | Build StraturaOS (ISO, SD card, Docker) |
| `clean` | Clean build directory |
| `help` | Show help |

**Build targets:**
- `iso` - x86_64: creates ISO + Docker image (incremental)
- `rpi5` - ARM64: creates SD card image + Docker image (incremental)
- `all` - Build both targets (clean build, default)

## Output Files

```
release/1.0/
├── arm64/
│   └── straturaos-1.0-rpi5-arm64-YYYYMMDD-HHMM.img
├── iso/
│   └── straturaos-1.0-x86_64-amd64-YYYYMMDD-HHMM.iso
└── docker/
    ├── straturaos-1.0-rpi5-arm64-YYYYMMDD-HHMM.tar
    └── straturaos-1.0-x86_64-amd64-YYYYMMDD-HHMM.tar
```

**Docker images:**
- `straturaos:latest-arm64` - RPi5 build
- `straturaos:latest-amd64` - x86_64 build

## Deploying

### RPi5 - Flash SD Card

```bash
sudo dd if=release/1.0/arm64/straturaos-*.img of=/dev/sdX bs=4M status=progress
sync
```

### x86_64 - Boot ISO in VM

```bash
# QEMU
qemu-system-x86_64 -cdrom release/1.0/iso/straturaos-*.iso -m 2048 -enable-kvm

# Proxmox - Upload ISO and create VM via web UI
scp release/1.0/iso/straturaos-*.iso root@proxmox:/var/lib/vz/template/iso/
```

### Docker

```bash
# Images are created automatically during build
docker run -it straturaos:latest-amd64 /bin/bash   # x86_64
docker run -it straturaos:latest-arm64 /bin/bash   # RPi5/ARM64

# Or import from tarball
docker import release/1.0/docker/straturaos-*-amd64-*.tar straturaos:latest-amd64
docker import release/1.0/docker/straturaos-*-arm64-*.tar straturaos:latest-arm64
```

## Project Structure

```
/home/straturaos/
├── build.sh              # Main build script
├── buildroot/            # Buildroot (cloned by setup)
├── buildroot-external/   # Custom packages and configs
│   ├── configs/          # Defconfig files
│   ├── package/          # Custom packages
│   └── board/            # Board-specific files
└── release/              # Output images
```

## License

StraturaOS is licensed under the GNU License. See [LICENSE](LICENSE) for details.
