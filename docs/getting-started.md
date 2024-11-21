# Getting Started with straturaOS

## Overview
straturaOS is a custom operating system for Raspberry Pi 5, built on the Yocto Project with container support, over-the-air updates, and advanced device management capabilities.

## Prerequisites
- Linux development machine
- At least 100GB free disk space
- Git 2.25+
- Python 3.8+
- Required packages:
  ```bash
  sudo apt-get install gawk wget git diffstat unzip texinfo gcc build-essential \
  chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils \
  iputils-ping python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev pylint \
  xterm python3-subunit mesa-common-dev zstd liblz4-tool
  ```

## Quick Start

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/stratura-os.git
   cd stratura-os
   ```

2. Initialize build environment:
   ```bash
   source oe-init-build-env build
   ```

3. Configure build:
   ```bash
   # Copy default configuration
   cp ../meta-stratura/conf/templates/default.conf.sample conf/local.conf
   ```

4. Build the image:
   ```bash
   bitbake stratura-image
   ```

5. Flash to SD card:
   ```bash
   sudo dd if=tmp/deploy/images/raspberrypi5/stratura-image.wic of=/dev/sdX bs=4M status=progress
   ```

## First Boot
On first boot, straturaOS will:
1. Generate unique device identity
2. Configure networking
3. Register with management platform
4. Pull and start configured containers

## Next Steps
- [Architecture Overview](architecture/overview.md)
- [Development Guide](development/building.md)
- [Configuration Reference](reference/configuration.md)
