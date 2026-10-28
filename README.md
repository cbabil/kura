<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/banner-dark.png">
    <source media="(prefers-color-scheme: light)" srcset=".github/banner-light.png">
    <img src=".github/banner-dark.png" alt="Kura" width="700">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/cbabil/kura/actions/workflows/ci.yml"><img src="https://github.com/cbabil/kura/actions/workflows/ci.yml/badge.svg?branch=dev" alt="CI"></a>
  <img src="https://img.shields.io/badge/debian-trixie-A81D33?logo=debian" alt="Debian Trixie">
  <img src="https://img.shields.io/badge/platform-x86__64%20%7C%20arm64-blue" alt="Platform">
  <img src="https://img.shields.io/badge/license-GPL--3.0-green" alt="License">
  <img src="https://img.shields.io/github/v/tag/cbabil/kura?label=version&color=orange" alt="Version">
</p>

# Kura

A lightweight home-server OS built on Debian 13 (Trixie) for the Raspberry Pi 5 and x86_64. Hardened Debian with Docker, nothing else running that you didn't ask for, and no cloud service to talk to. Flash it with [Etchwise](#etchwise) to choose the hostname, user, password, SSH keys, Wi-Fi, time zone and keyboard before the first boot.

## Features

- **Debian-based**: Built on Debian 13 (Trixie) for broad hardware and package support
- **mmdebstrap rootfs**: Reproducible, minimal root filesystem generation
- **Docker built in**: Docker Engine and Compose from Docker's APT repository (signing key fingerprint pinned)
- **First boot**: grows the root partition to fill the disk, generates this device's own SSH host keys and machine ID, and applies the settings an imager left on the boot partition (`kura-setup.json`)
- **Four targets**: RPi5 SD card image, x86_64 PC disk image (UEFI, Secure Boot, e.g. Intel NUC), a small PC installer USB image that puts Kura on a PC's internal drive, and a Docker rootfs
- **Login screen**: a boot splash (PC) and a console login screen with the address, the exact `ssh` command, service status and whether the Etchwise setup was applied
- **Security**: hardening at boot (kernel parameters, SSH, audit rules, firewall, filesystem mounts)
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
git clone https://github.com/cbabil/kura.git .

# Create local config from template
cp .env.example .env

# Setup (installs host dependencies; builds need root)
sudo ./build.sh setup

# Optional: create a system-wide symlink for convenience
sudo ln -sf "$(pwd)/build.sh" /usr/local/bin/kura
```

### 4. Build

```bash
sudo ./build.sh build all            # docker, pc, pc-installer and rpi5
sudo ./build.sh build pc             # the x86_64 PC disk image
sudo ./build.sh build pc-installer   # the PC installer USB image
sudo ./build.sh build rpi5           # the Raspberry Pi 5 SD card image

# Or with the symlink:
sudo kura build pc
```

**Note:** The Pi and PC images boot with Docker ready and work offline. Building needs internet for Debian and Docker packages.

### CI builds

GitHub Actions builds the Pi image, the PC image and the PC installer on every push to `dev` that changes build inputs, and on manual runs (**Actions → Images → Run workflow**). The PC image is also booted headless under UEFI **without internet**, once with a `kura-setup.json` on its EFI partition and once without, to check that:
- first boot finishes and grows the root partition;
- the setup file is applied (SSH key login as the new user, passwords off, hostname, Wi-Fi, time zone) and deleted;
- without it, the default password only reaches a forced change;
- the core services are running and Docker answers;
- two boots of the same image get different SSH host keys and machine IDs;
- the PC installer, booted from a virtual USB key with a setup file, installs the PC image on a blank virtual drive, which is then booted and checked the same way.

Each boot also saves screenshots of the splash and the login screen with the logs.

Dev runs only build and boot-test the images; release runs also upload them (`kura-pc-<sha>` with the installer, `kura-rpi5-<sha>`, kept 1 day) for the release job. They are **test builds** with `.env.example`'s default credentials, not for distribution. To run the boot test locally on Linux with QEMU:

```bash
tests/boot/boot-test.sh release/<version>/pc/kura-*.img boot-a 2222 --setup
```

### Releases

Pushing a `v*` tag builds the images and publishes a GitHub Release with the Pi image, the PC image and the PC installer (`.img.zst`), `SHA512SUMS`, `manifest.json` and `etchwise.json` (the OS list Etchwise reads). Every asset is signed keylessly with [Sigstore](https://www.sigstore.dev/) by the release workflow itself, so there is no signing key to manage; each asset ships with a `<asset>.sigstore.json` bundle. To verify a download (needs [cosign](https://github.com/sigstore/cosign)):

```bash
scripts/release/verify-release.sh kura-0.4.1-rpi5-arm64-20261027-0001.img.zst v0.4.1
```

Release images are built from `.env.example`: the `admin` password must be replaced at the first login and root has no password (see [Default Credentials](#default-credentials)).

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

**Branding**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_BRAND` | Lowercase prefix for paths, services, user/group | *(see brand-defaults.sh)* |
| `OS_NAME` | Display name shown in banners, MOTD, logs | *(see brand-defaults.sh)* |
| `OS_COLOR` | Brand accent color (hex) | `#9146FF` |

**Distribution**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_VERSION` | Release version baked into images | `0.0.1` |
| `OS_HOSTNAME` | Default hostname | `kura` |
| `OS_USER` | Login user (SSH password auth) | `admin` |
| `OS_USER_PASSWD` | Login user password (plaintext) | `admin` |
| `OS_ROOT_PASSWD` | Root console password (plaintext; root SSH is key-only). Empty locks root | empty (locked) |
| `OS_USER_PASSWD_EXPIRE` | Force the login user to set a new password at first login; `false` keeps `OS_USER_PASSWD` | `true` |
| `OS_ISSUE` | Tagline on the login screen and the SSH welcome | `The lightweight OS for your home server.` |

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
| `OS_PC_ROOTFS_SIZE` | PC image root partition size (firmware, all kernel modules) | `3G` |

**Build Directories**

| Variable | Description | Default |
|----------|-------------|---------|
| `OS_TMP` | Temp directory for builds | `/home/${OS_BRAND}/tmp` |

## Commands

| Command | Description |
|---------|-------------|
| `setup` | Install host dependencies for Debian builds |
| `build [target]` | Build OS image (mmdebstrap + overlays) |
| `clean` | Remove build rootfs and temp files |
| `cleanup` | Remove old build artifacts and temp files |
| `help` | Show help |

Run `setup` and `build` with `sudo` (mmdebstrap, chroot and loop devices need root). Every build starts from a fresh rootfs.

**Build targets:**
- `docker` - a minimal rootfs tarball for the build host's architecture, imported as `kura:latest-<arch>`
- `pc` - the x86_64 UEFI PC disk image
- `pc-installer` - the small USB installer that writes the PC image to a PC's internal drive
- `rpi5` - the ARM64 Raspberry Pi 5 SD card image
- `all` (the default) - docker, pc, pc-installer and rpi5

## Output Files

```
release/<version>/
├── arm64/
│   └── <brand>-<version>-rpi5-arm64-YYYYMMDD-NNNN.img
├── pc/
│   └── <brand>-<version>-x86_64-amd64-YYYYMMDD-NNNN.img
├── pc-installer/
│   └── <brand>-<version>-x86_64-installer-YYYYMMDD-NNNN.img
└── docker/
    └── <brand>-<version>-<arch>-YYYYMMDD-NNNN.tar   # the build host's architecture
```

Each directory also holds `SHA512SUMS`. `NNNN` is an auto-incremented build sequence number (zero-padded, stored in `.build-number`).

**Docker images:** `kura:latest-amd64` (x86_64 hosts; `amd64` is Docker's and Debian's name for x86_64) or `kura:latest-arm64` (ARM64 hosts), also tagged `kura:<version>-<arch>-<NNNN>`.

## Deploying

### Default Credentials

| User | Password | SSH Access |
|------|----------|------------|
| `admin` | `admin`, expired: the first SSH or console login must set a new one | Password auth |
| `root` | locked | None by password; use `sudo` from `admin` |

The `admin` password only gets you to the change-password prompt, so no device keeps it. Root has no password: with root locked, systemd's emergency mode can't open a shell, so a system that won't boot is repaired from another machine (or build with a private `OS_ROOT_PASSWD`). Change the defaults in `.env` (`OS_USER`, `OS_USER_PASSWD`, `OS_ROOT_PASSWD`) before building; set `OS_USER_PASSWD_EXPIRE="false"` to keep a private `OS_USER_PASSWD`.

### Etchwise

Etchwise (a multi-device imager based on Raspberry Pi Imager) lists Kura under Raspberry Pi 5 and Intel NUC (from each release's `etchwise.json`). The entries are:

| Device in Etchwise | Image | Download |
|---|---|---|
| Raspberry Pi 5 | **Kura &lt;version&gt;** | about 250 MB |
| Intel NUC | **Kura &lt;version&gt; installer (PC)**: puts Kura on the PC's internal drive | about 27 MB |
| Intel NUC | **Kura &lt;version&gt; (PC)**: runs from the USB drive or SSD it is written to | about 390 MB |

Its setup screens become `kura-setup.json` on the boot partition (the EFI partition on a PC); first boot validates it, applies it before SSH starts, and deletes it (it holds the password hash and Wi-Fi key). An invalid file is ignored and the image defaults stay (`admin`/`admin` with a forced change); the login screen then says "setup ignored" and why. **The user name must be a new name**: lowercase letters, digits, `_` or `-`, at most 32 characters, and not a name the system already has (such as `root`, `daemon` or `docker`). Format and rules: `scripts/common/firstboot-setup.sh`.

### RPi5 - Flash SD Card

Write **Kura &lt;version&gt;** with Etchwise (choose Raspberry Pi 5), or by hand:

```bash
zstd -dc kura-*-rpi5-arm64-*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress   # a release
sudo dd if=release/<version>/arm64/kura-*.img of=/dev/sdX bs=4M status=progress    # a local build
sync
```

Boot the Pi on your network and wait for first boot to finish (it grows the root partition). The console login screen shows the address and the exact `ssh` command; with the defaults that is `ssh admin@<address>`. If the root partition is too small for the image, the build stops and names the `OS_ROOTFS_SIZE` to set.

### PC (Intel NUC) - USB drive or SSD

**Install on the internal drive (recommended).** Write **Kura &lt;version&gt; installer (PC)** with Etchwise (choose **Intel NUC**) to a USB key, plug an Ethernet cable into the NUC and boot it from the key (F10 on most NUCs). The installer:
- downloads the latest Kura PC image (whatever the installer's own version) and checks it;
- picks the one internal drive (never the key, removable media, USB drives or SD cards; it stops if there is none or more than one);
- waits 10 seconds so any key cancels, then writes and reads the drive back;
- hands over the Etchwise setup, and turns the PC off.

Remove the key and turn the NUC on. Build it yourself with `sudo ./build.sh build pc-installer`.

**Run from a USB drive or SSD.** The PC image boots on UEFI machines (Secure Boot can stay on) and keeps running from the drive it is written to. Write **Kura &lt;version&gt; (PC)** with Etchwise (choose **Intel NUC**), or by hand:

```bash
zstd -dc kura-*-x86_64-amd64-*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress
sync
```

Plug it into the NUC, pick it in the boot menu (F10 on most NUCs), and wait for first boot to finish (it grows the root partition to the whole drive). It also runs in a VM: `qemu-system-x86_64 -machine q35 -bios /usr/share/ovmf/OVMF.fd -drive file=kura.img,format=raw,if=virtio -m 2048 -enable-kvm`.

### Docker

`build docker` (and `build all`) creates a minimal rootfs tarball for the build host's architecture and imports it into the local Docker daemon. It has no systemd or Docker inside.

```bash
# Run a built image
docker run -it kura:latest-amd64 /bin/bash   # x86_64
docker run -it kura:latest-arm64 /bin/bash   # RPi5/ARM64

# Import from tarball (e.g. on another machine)
docker import release/<version>/docker/kura-*-amd64-*.tar kura:latest-amd64
docker import release/<version>/docker/kura-*-arm64-*.tar kura:latest-arm64
```

## Project Structure

```
├── .env.example          # Build config template (cp to .env)
├── .env                  # Local build config (gitignored)
├── build.sh              # Main build script
├── config/               # Package lists per target
├── packages/             # OS package sources (os-config, os-security)
├── overlay/              # Filesystem overlays (common, x86_64)
├── scripts/              # Build scripts (common, rpi5, x86_64, pc-installer, docker, release)
├── tests/shell/          # Shell script tests (bats)
├── tests/boot/           # QEMU boot and install tests (CI)
└── release/              # Output images
```

## Rebranding

The OS can be rebranded by editing variables in `.env`:

```bash
OS_BRAND="myco"           # paths: /etc/myco/, services: myco-config
OS_NAME="MyCo OS"         # display name in banners and logs
```

Default brand values are defined in `scripts/common/brand-defaults.sh` (single source of truth).

After changing these values, rebuild (`./build.sh build all`). The build system propagates branding through:

- **Build scripts**: `${OS_BRAND}` substitution for paths, artifact names, Docker tags
- **Service files**: `__BRAND__` / `__BRAND_NAME__` placeholders, sed-replaced at install
- **Runtime**: `/etc/kura/brand.env` (fixed path) generated at build, read by the MOTD, the login screen and the SSH welcome

**What stays static** (not affected by rebranding):
- Source filenames in `packages/` (installed under branded names)
- The bootstrap path `/etc/kura/brand.env` (hardcoded discovery point)
- The splash artwork (`overlay/x86_64/usr/share/plymouth/themes/kura/logo.png`, pre-rendered from `.github/splash.html`)
- The installer's release repository (`cbabil/kura`)

## License

Licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for details.
