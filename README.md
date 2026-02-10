# StraturaOS

StraturaOS is a custom operating system built on Debian 13 (Trixie) using mmdebstrap for Raspberry Pi 5 and x86_64 VMs. It offers container support, device management, and security hardening for IoT and edge computing applications.

## Features

- **Debian-based**: Built on Debian 13 (Trixie) for broad hardware and package support
- **mmdebstrap rootfs**: Reproducible, minimal root filesystem generation
- **Three targets**: RPi5 SD card image, x86_64 ISO, and Docker containers
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
| `/tmp` | 2GB | 5GB | Temporary build files |
| `/home` | 5GB | 10GB | Source, builds, releases |
| `swap` | 2GB | 4GB | Swap |
| **Total** | **20GB** | **35GB** | |

**Note:** All configurable values are in `.env`. Copy the template on first setup: `cp .env.example .env`

### 2. Install StraturaOS

```bash
# Create project directory
mkdir -p /home/straturaos
cd /home/straturaos

# Clone repository (or copy via SCP)
git clone <repo-url> .

# Create local config from template
cp .env.example .env

# Setup (installs host dependencies)
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

**Note:** Docker images are created automatically with each build. On the ISO target, Docker itself is deferred to firstboot; on RPi5, Docker is included directly in the image.

## Configuration

All tunable build values live in `.env` at the project root. Copy the template on first setup (`cp .env.example .env`), edit values, and rebuild.

**Config Version**

| Variable | Description | Default |
|----------|-------------|---------|
| `STRATURAOS_CONF_VERSION` | .env format version (for upgrade warnings) | `2` |

**Debian Base**

| Variable | Description | Default |
|----------|-------------|---------|
| `STRATURAOS_DEBIAN_SUITE` | Debian suite for mmdebstrap | `trixie` |
| `STRATURAOS_DEBIAN_MIRROR` | APT mirror URL | `http://deb.debian.org/debian` |
| `STRATURAOS_CROSS_BUILD` | Cross-compilation mode | `auto` (auto\|yes\|no) |

**Parallelism**

| Variable | Description | Default |
|----------|-------------|---------|
| `STRATURAOS_PARALLEL_JOBS` | Parallel make jobs | `$(nproc)` |

**Distribution**

| Variable | Description | Default |
|----------|-------------|---------|
| `STRATURAOS_VERSION` | Release version baked into images | `2.0` |
| `STRATURAOS_HOSTNAME` | Default hostname | `straturaos` |
| `STRATURAOS_ROOT_PASSWD` | Root password (plaintext) | `stratura` |
| `STRATURAOS_ISSUE` | Login banner | `Welcome to StraturaOS` |

**Network**

| Variable | Description | Default |
|----------|-------------|---------|
| `STRATURAOS_DHCP_INTERFACE` | Interface for DHCP at first boot | `eth0` |

**Filesystem**

| Variable | Description | Default |
|----------|-------------|---------|
| `STRATURAOS_ROOTFS_SIZE` | RPi5 rootfs ext4 + partition size | `2G` |

**Build Directories**

| Variable | Description | Default |
|----------|-------------|---------|
| `STRATURAOS_TMP` | Temp directory for builds | `/home/straturaos/tmp` |

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Install host dependencies for Debian builds |
| `build [target]` | Build StraturaOS image (mmdebstrap + overlays) |
| `clean` | Remove build rootfs and temp files |
| `help` | Show help |

**Build targets:**
- `iso` - x86_64: creates ISO + Docker image (incremental)
- `rpi5` - ARM64: creates SD card image + Docker image (incremental)
- `docker` - Docker image only
- `all` - Build both targets (clean build, default)

## Output Files

```
release/2.0/
├── arm64/
│   └── straturaos-2.0-rpi5-arm64-YYYYMMDD-HHMM.img
├── iso/
│   └── straturaos-2.0-x86_64-amd64-YYYYMMDD-HHMM.iso
└── docker/
    ├── straturaos-2.0-rpi5-arm64-YYYYMMDD-HHMM.tar
    └── straturaos-2.0-x86_64-amd64-YYYYMMDD-HHMM.tar
```

**Docker images:**
- `straturaos:latest-arm64` - RPi5 build
- `straturaos:latest-amd64` - x86_64 build

## Deploying

### RPi5 - Flash SD Card

```bash
sudo dd if=release/2.0/arm64/straturaos-*.img of=/dev/sdX bs=4M status=progress
sync
```

### x86_64 - Boot ISO in VM

```bash
# QEMU
qemu-system-x86_64 -cdrom release/2.0/iso/straturaos-*.iso -m 2048 -enable-kvm

# Proxmox - Upload ISO and create VM via web UI
scp release/2.0/iso/straturaos-*.iso root@proxmox:/var/lib/vz/template/iso/
```

### Docker

```bash
# Images are created automatically during build
docker run -it straturaos:latest-amd64 /bin/bash   # x86_64
docker run -it straturaos:latest-arm64 /bin/bash   # RPi5/ARM64

# Or import from tarball
docker import release/2.0/docker/straturaos-*-amd64-*.tar straturaos:latest-amd64
docker import release/2.0/docker/straturaos-*-arm64-*.tar straturaos:latest-arm64
```

## Project Structure

```
/home/straturaos/
├── .env.example          # Build config template (cp to .env)
├── .env                  # Local build config (gitignored)
├── build.sh              # Main build script
├── config/               # Package lists per target
├── packages/             # Stratura package sources
├── overlay/              # Filesystem overlays (common, rpi5, x86_64)
├── scripts/              # Build scripts (common, rpi5, x86_64, docker)
├── tests/                # Unit tests (pytest)
└── release/              # Output images
```

## License

StraturaOS is licensed under the GNU License. See [LICENSE](LICENSE) for details.
