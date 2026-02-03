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
| `export` | Package + docker (no rebuild) |
| `release` | Build + package + docker (full release) |
| `clean` | Clean build directory |
| `cleanup` | Remove old artifacts (keeps last 2 builds) |
| `distclean` | Full clean (reset everything) |
| `install` | Install 'straturaos' command globally |
| `uninstall` | Remove global 'straturaos' command |

### Output Files

After a successful build:

- `straturaos-sdcard-YYYYMMDD.img` - SD card image (flash to hardware)
- `straturaos-docker-YYYYMMDD.tar` - Docker tarball (for `docker import`)
- Docker image: `straturaos:YYYYMMDD` / `straturaos:latest`

### Flashing to SD Card

```bash
sudo dd if=output/images/straturaos-sdcard-YYYYMMDD.img of=/dev/sdX bs=4M status=progress
sync
```

### Running in Docker

If built on another machine, import the tarball first:

```bash
docker import straturaos-docker-YYYYMMDD.tar straturaos:YYYYMMDD
docker tag straturaos:YYYYMMDD straturaos:latest
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
