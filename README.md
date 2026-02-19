<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset=".github/banner-light.png">
    <img src=".github/banner-dark.png" alt="FalkenOS" width="700">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/cbabil/FalkenOS/actions/workflows/ci.yml"><img src="https://github.com/cbabil/FalkenOS/actions/workflows/ci.yml/badge.svg?branch=dev" alt="CI"></a>
  <img src="https://img.shields.io/badge/debian-trixie-A81D33?logo=debian" alt="Debian Trixie">
  <img src="https://img.shields.io/badge/platform-x86__64%20%7C%20arm64-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-GPL-green" alt="License">
  <img src="https://img.shields.io/github/v/tag/cbabil/FalkenOS?label=version&color=orange" alt="Version">
</p>

# FalkenOS

A custom operating system built on Debian 13 (Trixie) using mmdebstrap for Raspberry Pi 5 and x86_64 VMs. It offers container support, device management, and security hardening for IoT and edge computing applications.

## Features

- **Debian-based**: Built on Debian 13 (Trixie) for broad hardware and package support
- **mmdebstrap rootfs**: Reproducible, minimal root filesystem generation
- **Three targets**: RPi5 SD card image, x86_64 ISO, and Docker containers
- **Container Support**: Integrated Docker runtime
- **Security**: Security hardening and monitoring tools
- **Network Management**: NetworkManager for flexible configuration
- **Rebrandable**: All user-visible branding controlled via `.env` variables

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

### 2. Prerequisites

The build VM needs a working HTTPS connection and up-to-date CA certificates:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git
```

If `apt-get update` fails with SSL errors (fresh minimal install), temporarily bypass TLS verification to bootstrap certificates:

```bash
sudo apt-get -o Acquire::https::Verify-Peer=false update
sudo apt-get install -y ca-certificates
sudo update-ca-certificates
```

### 3. Install

```bash
# Create project directory
mkdir -p /home/os-build
cd /home/os-build

# Clone repository (or rsync from dev machine)
git clone <repo-url> .

# Create local config from template
cp .env.example .env

# Setup (installs host dependencies)
./build.sh setup

# Optional: create a system-wide symlink for convenience
sudo ln -sf "$(pwd)/build.sh" /usr/local/bin/falkenos
```

### 4. Build

```bash
./build.sh build all        # Build all targets (clean build)
./build.sh build iso        # Build x86_64 only (incremental)
./build.sh build rpi5       # Build RPi5 only (incremental)

# Or with the symlink:
falkenos build iso
```

**Note:** Docker images are created automatically with each build. On the ISO target, Docker itself is deferred to firstboot; on RPi5, Docker is included directly in the image.

## Configuration

All tunable build values live in `.env` at the project root. Copy the template on first setup (`cp .env.example .env`), edit values, and rebuild.

**Config Version**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_CONF_VERSION` | .env format version (for upgrade warnings) | `4` |

**Debian Base**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_DEBIAN_SUITE` | Debian suite for mmdebstrap | `trixie` |
| `OS_DEBIAN_MIRROR` | APT mirror URL | `http://deb.debian.org/debian` |
| `OS_CROSS_BUILD` | Cross-compilation mode | `auto` (auto\|yes\|no) |

**Parallelism**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_PARALLEL_JOBS` | Parallel make jobs | `$(nproc)` |

**Bun Runtime**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_BUN_VERSION` | Bun version for supervisor | `1.2.4` |
| `OS_BUN_SHA256_X64` | SHA256 checksum for x86_64 binary | *(see .env.example)* |
| `OS_BUN_SHA256_AARCH64` | SHA256 checksum for aarch64 binary | *(see .env.example)* |

**Branding**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_BRAND` | Lowercase prefix for paths, services, user/group | *(see brand-defaults.sh)* |
| `OS_NAME` | Display name shown in banners, MOTD, logs | *(see brand-defaults.sh)* |
| `OS_COLOR` | Brand accent color (hex) | `#33ff00` |
| `OS_API_ENDPOINT` | API endpoint for connectivity checks | *(see brand-defaults.sh)* |
| `OS_WS_ENDPOINT` | WebSocket endpoint for supervisor | *(derived from API endpoint)* |
| `OS_REGISTRY` | Container registry for managed apps | *(see brand-defaults.sh)* |

**Supervisor WebSocket**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_WS_HEARTBEAT_INTERVAL` | Heartbeat ping interval (ms) | `30000` |
| `OS_WS_HEARTBEAT_TIMEOUT` | Connection dead timeout (ms) | `90000` |
| `OS_WS_RECONNECT_BASE` | Initial reconnect delay (ms, exponential backoff) | `1000` |
| `OS_WS_RECONNECT_MAX` | Maximum reconnect delay cap (ms) | `60000` |

**Distribution**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_VERSION` | Release version baked into images | `0.0.1` |
| `OS_HOSTNAME` | Default hostname | `${OS_BRAND}os` |
| `OS_USER` | Login user (SSH password auth) | `joshua` |
| `OS_USER_PASSWD` | Login user password (plaintext) | `joshua` |
| `OS_ROOT_PASSWD` | Root password (plaintext, key-only SSH) | `${OS_BRAND}` |
| `OS_ISSUE` | Login banner | `Welcome to ${OS_NAME}` |

**Network**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_DHCP_INTERFACE` | Interface for DHCP at first boot | `eth0` |

**Logging**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_JOURNAL_MAX_SIZE` | Max systemd journal size | `100M` |
| `OS_JOURNAL_MAX_FILE_SEC` | Max journal file age | `1week` |

**Filesystem**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_ROOTFS_SIZE` | RPi5 rootfs ext4 + partition size | `2G` |

**Build Directories**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_TMP` | Temp directory for builds | `/home/${OS_BRAND}os/tmp` |

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Install host dependencies for Debian builds |
| `build [target]` | Build OS image (mmdebstrap + overlays) |
| `clean` | Remove build rootfs and temp files |
| `help` | Show help |

**Build targets:**
- `iso` - x86_64: creates ISO + Docker image (incremental)
- `rpi5` - ARM64: creates SD card image + Docker image (incremental)
- `docker` - Docker image only
- `all` - Build both targets (clean build, default)

## Output Files

```
release/<version>/
├── arm64/
│   └── <brand>os-<version>-rpi5-arm64-YYYYMMDD-NNNN.img
├── iso/
│   └── <brand>os-<version>-x86_64-amd64-YYYYMMDD-NNNN.iso
└── docker/
    ├── <brand>os-<version>-rpi5-arm64-YYYYMMDD-NNNN.tar
    └── <brand>os-<version>-x86_64-amd64-YYYYMMDD-NNNN.tar
```

`NNNN` is an auto-incremented build sequence number (zero-padded, stored in `.build-number`).

**Docker images:**
- `<brand>os:latest-arm64` - RPi5 build
- `<brand>os:latest-amd64` - x86_64 build

## Deploying

### Default Credentials

| User | Password | SSH Access |
|------|----------|------------|
| `joshua` | `joshua` | Password auth |
| `root` | `falken` | Key-only (no password SSH) |

Change these in `.env` (`OS_USER`, `OS_USER_PASSWD`, `OS_ROOT_PASSWD`) before building.

### RPi5 - Flash SD Card

```bash
sudo dd if=release/<version>/arm64/<brand>os-*.img of=/dev/sdX bs=4M status=progress
sync
```

### x86_64 - Boot ISO in VM

```bash
# QEMU
qemu-system-x86_64 -cdrom release/<version>/iso/<brand>os-*.iso -m 2048 -enable-kvm

# Proxmox - Upload ISO and create VM via web UI
scp release/<version>/iso/<brand>os-*.iso root@proxmox:/var/lib/vz/template/iso/
```

### Docker

Docker images are created automatically with each build and imported into the local Docker daemon.

```bash
# Run a built image
docker run -it <brand>os:latest-amd64 /bin/bash   # x86_64
docker run -it <brand>os:latest-arm64 /bin/bash   # RPi5/ARM64

# Import from tarball (e.g. on another machine)
docker import release/<version>/docker/<brand>os-*-amd64-*.tar <brand>os:latest-amd64
docker import release/<version>/docker/<brand>os-*-arm64-*.tar <brand>os:latest-arm64
```

## Project Structure

```
├── .env.example          # Build config template (cp to .env)
├── .env                  # Local build config (gitignored)
├── build.sh              # Main build script
├── config/               # Package lists per target
├── packages/             # OS package sources (os-config, os-security)
├── overlay/              # Filesystem overlays (common, rpi5, x86_64)
├── scripts/              # Build scripts (common, rpi5, x86_64, docker)
├── supervisor/           # Node.js device supervisor (Bun/WebSocket)
├── tests/shell/          # Shell script tests (bats)
└── release/              # Output images
```

## Rebranding

The OS can be rebranded by editing variables in `.env`:

```bash
OS_BRAND="myco"           # paths: /etc/myco/, services: myco-supervisor
OS_NAME="MyCo OS"         # display name in banners and logs
OS_API_ENDPOINT="https://api.myco.io"
OS_WS_ENDPOINT="wss://api.myco.io/ws"  # optional, derived from API endpoint
```

Default brand values are defined in `scripts/common/brand-defaults.sh` (single source of truth).

After changing these values, rebuild (`./build.sh build all`). The build system propagates branding through:

- **Build scripts**: `${OS_BRAND}` substitution for paths, artifact names, Docker tags
- **Service files**: `__BRAND__` / `__BRAND_NAME__` placeholders, sed-replaced at install
- **Runtime**: `/etc/${BRAND}/brand.env` generated at build, read by supervisor and MOTD
- **Dockerfile**: `--build-arg BRAND` for container user/group/workdir

**What stays static** (not affected by rebranding):
- Source filenames in `packages/` (installed under branded names)
- The bootstrap path `/etc/falken/brand.env` (hardcoded discovery point)

## License

Licensed under the GNU License. See [LICENSE](LICENSE) for details.
