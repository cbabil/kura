# Custom Linux OS

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

### 2. Install

```bash
# Create project directory
mkdir -p /home/os-build
cd /home/os-build

# Clone repository (or copy via SCP)
git clone <repo-url> .

# Create local config from template
cp .env.example .env

# Setup (installs host dependencies)
./build.sh setup
```

### 3. Build

```bash
./build.sh build all        # Build all targets (clean build)
./build.sh build iso        # Build x86_64 only (incremental)
./build.sh build rpi5       # Build RPi5 only (incremental)
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

**Branding**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_BRAND` | Lowercase prefix for paths, services, user/group | *(see brand-defaults.sh)* |
| `OS_NAME` | Display name shown in banners, MOTD, logs | *(see brand-defaults.sh)* |
| `OS_API_ENDPOINT` | API endpoint for connectivity checks | *(see brand-defaults.sh)* |
| `OS_REGISTRY` | Container registry for managed apps | *(see brand-defaults.sh)* |

**Distribution**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_VERSION` | Release version baked into images | `2.0` |
| `OS_HOSTNAME` | Default hostname | `${OS_BRAND}os` |
| `OS_ROOT_PASSWD` | Root password (plaintext) | `${OS_BRAND}` |
| `OS_ISSUE` | Login banner | `Welcome to ${OS_NAME}` |

**Network**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_DHCP_INTERFACE` | Interface for DHCP at first boot | `eth0` |

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
│   └── <brand>os-<version>-rpi5-arm64-YYYYMMDD-HHMM.img
├── iso/
│   └── <brand>os-<version>-x86_64-amd64-YYYYMMDD-HHMM.iso
└── docker/
    ├── <brand>os-<version>-rpi5-arm64-YYYYMMDD-HHMM.tar
    └── <brand>os-<version>-x86_64-amd64-YYYYMMDD-HHMM.tar
```

**Docker images:**
- `<brand>os:latest-arm64` - RPi5 build
- `<brand>os:latest-amd64` - x86_64 build

## Deploying

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

```bash
# Images are created automatically during build
docker run -it <brand>os:latest-amd64 /bin/bash   # x86_64
docker run -it <brand>os:latest-arm64 /bin/bash   # RPi5/ARM64

# Or import from tarball
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
├── supervisor/           # Node.js device supervisor (Docker-based)
├── tests/                # Unit tests (pytest)
└── release/              # Output images
```

## Rebranding

The OS can be rebranded by editing variables in `.env`:

```bash
OS_BRAND="myco"           # paths: /etc/myco/, services: myco-supervisor
OS_NAME="MyCo OS"         # display name in banners and logs
OS_API_ENDPOINT="https://api.myco.io"
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
