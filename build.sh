#!/bin/bash
# StraturaOS Build Script
# Usage: ./build.sh [command]
#
# Commands:
#   setup     - Clone Buildroot and setup environment
#   config    - Configure build (menuconfig)
#   build     - Build the image
#   package   - Create dated images, rootfs.tar, and ISO
#   docker    - Create Docker image from rootfs
#   iso       - Create bootable ISO (x86_64 only)
#   release   - Build + package + docker
#   clean     - Clean build directory
#   distclean - Full clean (reset everything)

set -e

# Temporary directory - change this if /tmp is too small
STRATURAOS_TMP="${STRATURAOS_TMP:-/home/straturaos/tmp}"
mkdir -p "${STRATURAOS_TMP}" 2>/dev/null || true
export TMPDIR="${STRATURAOS_TMP}"
export GOTMPDIR="${STRATURAOS_TMP}"
export GOCACHE="${STRATURAOS_TMP}/.cache/go-build"
mkdir -p "${GOCACHE}" 2>/dev/null || true

# Allow building as root (required for some packages)
export FORCE_UNSAFE_CONFIGURE=1

# Resolve symlinks to get the real script location
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

# Project root directory (where buildroot and buildroot-external live)
PROJECT_DIR="${SCRIPT_DIR}"

BUILDROOT_DIR="${PROJECT_DIR}/buildroot"

# EXTERNAL_DIR: use subdirectory if exists, otherwise use PROJECT_DIR itself
if [ -d "${PROJECT_DIR}/buildroot-external" ]; then
    EXTERNAL_DIR="${PROJECT_DIR}/buildroot-external"
else
    EXTERNAL_DIR="${PROJECT_DIR}"
fi
BUILD_DIR="${BUILDROOT_DIR}/output"
IMAGES_DIR="${BUILD_DIR}/images"
RELEASE_DIR="${PROJECT_DIR}/release"
BUILD_DATE=$(date +%Y%m%d)
BUILD_TIME=$(date +%H%M)
VERSION="1.0"

# Detect architecture from config
detect_arch() {
    if [ -f "${BUILDROOT_DIR}/.config" ]; then
        if grep -q "BR2_aarch64=y" "${BUILDROOT_DIR}/.config"; then
            echo "arm64"
        elif grep -q "BR2_x86_64=y" "${BUILDROOT_DIR}/.config"; then
            echo "amd64"
        else
            echo "unknown"
        fi
    else
        echo "unknown"
    fi
}

# Detect variant from config
detect_variant() {
    if [ -f "${BUILDROOT_DIR}/.config" ]; then
        if grep -q "straturaos_x86_64_defconfig" "${BUILDROOT_DIR}/.config" 2>/dev/null || \
           grep -q "BR2_x86_64=y" "${BUILDROOT_DIR}/.config"; then
            echo "x86_64"
        elif grep -q "bcm2712" "${BUILDROOT_DIR}/.config" 2>/dev/null; then
            echo "rpi5"
        else
            echo "generic"
        fi
    else
        echo "generic"
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[StraturaOS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_status "Checking build dependencies..."

    # All required packages for building StraturaOS
    local REQUIRED_PKGS="
        build-essential
        git
        make
        gcc
        g++
        libncurses5-dev
        wget
        cpio
        unzip
        rsync
        bc
        libssl-dev
        file
        xorriso
        grub-pc-bin
        grub-efi-amd64-bin
        mtools
        dosfstools
        squashfs-tools
        libffi-dev
        python3-dev
        texinfo
        bzip2
        patch
        perl
        tar
        gzip
        sed
        binutils
        diffutils
        bash
        gawk
    "

    local missing=""
    for pkg in ${REQUIRED_PKGS}; do
        if ! dpkg -l "${pkg}" 2>/dev/null | grep -q "^ii"; then
            missing="${missing} ${pkg}"
        fi
    done

    if [ -n "${missing}" ]; then
        print_status "Installing missing packages:${missing}"
        apt-get update
        apt-get install -y ${missing}
        print_status "Dependencies installed successfully"
    else
        print_status "All dependencies are installed"
    fi
}

install_dependencies() {
    check_dependencies
}

setup_buildroot() {
    print_status "Setting up Buildroot..."

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_status "Cloning Buildroot..."
        git clone https://github.com/buildroot/buildroot "${BUILDROOT_DIR}"
        cd "${BUILDROOT_DIR}"
        # Get latest stable release tag (format: YYYY.MM or YYYY.MM.x)
        LATEST_TAG=$(git tag -l '20*' | grep -E '^[0-9]{4}\.[0-9]{2}(\.[0-9]+)?$' | sort -V | tail -1)
        print_status "Using Buildroot ${LATEST_TAG}"
        git checkout "${LATEST_TAG}"
    else
        print_status "Buildroot already exists at ${BUILDROOT_DIR}"
    fi

    print_status "Setup complete!"
}

configure_build() {
    local TARGET=${1:-rpi5}
    print_status "Configuring StraturaOS build for ${TARGET}..."

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_error "Buildroot not found. Run './build.sh setup' first."
        exit 1
    fi

    cd "${BUILDROOT_DIR}"

    # Remove old config files
    rm -f "${BUILDROOT_DIR}/.config" "${BUILDROOT_DIR}/.config.old" 2>/dev/null || true

    # Load defconfig
    case "${TARGET}" in
        rpi5|rpi)
            make BR2_EXTERNAL="${EXTERNAL_DIR}" straturaos_defconfig
            ;;
        iso|x86_64|x86|vm)
            make BR2_EXTERNAL="${EXTERNAL_DIR}" straturaos_x86_64_defconfig
            ;;
        *)
            print_error "Unknown target: ${TARGET}. Use 'rpi5' or 'iso'"
            exit 1
            ;;
    esac

    # Check for legacy issues and show what's causing them
    if [ -f "${BUILDROOT_DIR}/.config" ] && grep -q "^BR2_LEGACY=y" "${BUILDROOT_DIR}/.config"; then
        print_error "Legacy config detected. Finding cause..."
        grep -B3 "select BR2_LEGACY" "${BUILDROOT_DIR}/Config.in.legacy" 2>/dev/null | grep "^config " | while read line; do
            opt=$(echo "$line" | sed 's/config //')
            if grep -q "^${opt}=y" "${BUILDROOT_DIR}/.config" 2>/dev/null; then
                print_error "CAUSE: ${opt}=y"
            fi
        done
        exit 1
    fi

    print_status "Configuration loaded!"
}

run_menuconfig() {
    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_error "Buildroot not found. Run './build.sh setup' first."
        exit 1
    fi

    cd "${BUILDROOT_DIR}"
    make BR2_EXTERNAL="${EXTERNAL_DIR}" menuconfig
}

build_single_target() {
    local TARGET=$1
    local CLEAN=${2:-no}
    print_status "Building StraturaOS for ${TARGET}..."

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_error "Buildroot not found. Run './build.sh setup' first."
        exit 1
    fi

    # Always cleanup before build to free space
    cleanup_old_artifacts 1

    cd "${BUILDROOT_DIR}"

    # Only full clean if requested
    if [ "${CLEAN}" = "clean" ]; then
        print_status "Full clean requested..."
        # Backup downloads to project directory (not /tmp which may be small)
        local DL_BACKUP="${PROJECT_DIR}/.dl-backup"
        if [ -d "${BUILDROOT_DIR}/dl" ]; then
            rm -rf "${DL_BACKUP}"
            mv "${BUILDROOT_DIR}/dl" "${DL_BACKUP}" || true
        fi
        # Clean everything
        print_status "Running distclean..."
        make distclean || {
            print_warning "distclean failed, removing output directory manually..."
            rm -rf "${BUILDROOT_DIR}/output"
            rm -f "${BUILDROOT_DIR}/.config"
            rm -f "${BUILDROOT_DIR}/.config.old"
        }
        # Restore downloads
        if [ -d "${DL_BACKUP}" ]; then
            mv "${DL_BACKUP}" "${BUILDROOT_DIR}/dl" || true
        fi
    fi

    # Configure for target (only if config doesn't exist or target changed)
    configure_build "${TARGET}"

    cd "${BUILDROOT_DIR}"

    # Build (incremental by default)
    print_status "Building (incremental)..."
    make BR2_EXTERNAL="${EXTERNAL_DIR}" -j$(nproc)

    # Export artifacts
    export_artifacts
}

build_image() {
    local TARGET=${1:-all}
    local CLEAN=${2:-no}

    print_status "Building StraturaOS..."

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_error "Buildroot not found. Run './build.sh setup' first."
        exit 1
    fi

    if [ "${TARGET}" = "all" ]; then
        # Build all targets - requires clean between them (different arch)
        print_status "Building all targets (rpi5 + iso)..."
        build_single_target "rpi5" "clean"
        build_single_target "iso" "clean"
        print_status "All targets built successfully!"
    else
        # Build single target - incremental by default, clean only if explicitly requested
        build_single_target "${TARGET}" "${CLEAN}"
    fi
}

clean_build() {
    print_status "Cleaning build..."

    if [ -d "${BUILDROOT_DIR}" ]; then
        cd "${BUILDROOT_DIR}"
        make clean
    fi

    print_status "Clean complete!"
}

cleanup_old_artifacts() {
    local KEEP_COUNT=${1:-1}
    print_status "Cleaning up old artifacts (keeping last ${KEEP_COUNT})..."

    # Show disk usage before
    echo ""
    df -h / 2>/dev/null | head -2
    echo ""

    # Cleanup old releases in each version/arch directory
    if [ -d "${RELEASE_DIR}" ]; then
        for version_dir in "${RELEASE_DIR}"/*/; do
            if [ ! -d "$version_dir" ]; then continue; fi
            for arch_dir in "${version_dir}"/*/; do
            if [ -d "$arch_dir" ]; then
                local ARCH=$(basename "$arch_dir")

                # Cleanup old .img files
                local IMG_COUNT=$(ls -1 "${arch_dir}"straturaos-*.img 2>/dev/null | wc -l | tr -d ' ')
                if [ "${IMG_COUNT}" -gt "${KEEP_COUNT}" ]; then
                    print_status "Removing old images in ${ARCH}..."
                    ls -1t "${arch_dir}"straturaos-*.img 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read img; do
                        echo "  Removing: $(basename ${img})"
                        rm -f "${img}" "${img}.sign"
                    done
                fi

                # Cleanup old .qcow2 files
                local QCOW_COUNT=$(ls -1 "${arch_dir}"straturaos-*.qcow2 2>/dev/null | wc -l | tr -d ' ')
                if [ "${QCOW_COUNT}" -gt "${KEEP_COUNT}" ]; then
                    print_status "Removing old qcow2 images in ${ARCH}..."
                    ls -1t "${arch_dir}"straturaos-*.qcow2 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read img; do
                        echo "  Removing: $(basename ${img})"
                        rm -f "${img}" "${img}.sign"
                    done
                fi

                # Cleanup old .tar files
                local TAR_COUNT=$(ls -1 "${arch_dir}"straturaos-*.tar 2>/dev/null | wc -l | tr -d ' ')
                if [ "${TAR_COUNT}" -gt "${KEEP_COUNT}" ]; then
                    print_status "Removing old tarballs in ${ARCH}..."
                    ls -1t "${arch_dir}"straturaos-*.tar 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read tar; do
                        echo "  Removing: $(basename ${tar})"
                        rm -f "${tar}" "${tar}.sign"
                    done
                fi

                # Cleanup old .iso files
                local ISO_COUNT=$(ls -1 "${arch_dir}"straturaos-*.iso 2>/dev/null | wc -l | tr -d ' ')
                if [ "${ISO_COUNT}" -gt "${KEEP_COUNT}" ]; then
                    print_status "Removing old ISOs in ${ARCH}..."
                    ls -1t "${arch_dir}"straturaos-*.iso 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read iso; do
                        echo "  Removing: $(basename ${iso})"
                        rm -f "${iso}" "${iso}.sign"
                    done
                fi
            fi
            done
        done
    fi

    # Cleanup Docker if available
    if command -v docker &> /dev/null; then
        # Remove old straturaos images
        local DOCKER_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '^straturaos:' | grep -v ':latest' | sort -r || true)
        local DOCKER_COUNT=0
        if [ -n "${DOCKER_IMAGES}" ]; then
            DOCKER_COUNT=$(echo "${DOCKER_IMAGES}" | wc -l | tr -d ' ')
        fi

        if [ "${DOCKER_COUNT:-0}" -gt "${KEEP_COUNT}" ]; then
            print_status "Removing old Docker images..."
            echo "${DOCKER_IMAGES}" | tail -n +$((KEEP_COUNT + 1)) | while read img; do
                if [ -n "${img}" ]; then
                    echo "  Removing: ${img}"
                    docker rmi "${img}" 2>/dev/null || true
                fi
            done
        fi

        # Clean all unused Docker resources
        print_status "Cleaning unused Docker resources..."
        docker system prune -af 2>/dev/null || true
    fi

    # Clean temporary build files
    print_status "Cleaning temporary files..."
    rm -rf "${STRATURAOS_TMP}"/straturaos-* 2>/dev/null || true

    # Clean buildroot build cache
    if [ -d "${BUILDROOT_DIR}/output/build" ]; then
        local BUILD_SIZE=$(du -sm "${BUILDROOT_DIR}/output/build" 2>/dev/null | cut -f1)
        if [ "${BUILD_SIZE:-0}" -gt 1000 ]; then
            print_status "Cleaning buildroot build cache (${BUILD_SIZE}MB)..."
            rm -rf "${BUILDROOT_DIR}/output/build"/*
        fi
    fi

    # Clean buildroot target directory (prevents symlink conflicts)
    if [ -d "${BUILDROOT_DIR}/output/target" ]; then
        print_status "Cleaning buildroot target directory..."
        rm -rf "${BUILDROOT_DIR}/output/target"
    fi

    # Clean buildroot images directory
    if [ -d "${BUILDROOT_DIR}/output/images" ]; then
        print_status "Cleaning buildroot images directory..."
        rm -rf "${BUILDROOT_DIR}/output/images"/*
    fi

    # Clean buildroot download cache if over 5GB
    if [ -d "${BUILDROOT_DIR}/dl" ]; then
        local DL_SIZE=$(du -sm "${BUILDROOT_DIR}/dl" 2>/dev/null | cut -f1)
        if [ "${DL_SIZE:-0}" -gt 5000 ]; then
            print_status "Cleaning buildroot download cache (${DL_SIZE}MB)..."
            rm -rf "${BUILDROOT_DIR}/dl"/*
        fi
    fi

    # Clean system logs
    print_status "Cleaning old logs..."
    journalctl --vacuum-time=1d 2>/dev/null || true
    rm -f /var/log/*.gz /var/log/*.old 2>/dev/null || true

    # Clean apt cache
    if command -v apt-get &> /dev/null; then
        print_status "Cleaning apt cache..."
        apt-get clean 2>/dev/null || true
    fi

    # Clean Go cache (used by Docker build)
    if [ -d "${HOME}/.cache/go-build" ]; then
        print_status "Cleaning Go build cache..."
        rm -rf "${HOME}/.cache/go-build"
    fi
    if [ -d "/root/.cache/go-build" ]; then
        rm -rf "/root/.cache/go-build"
    fi

    # Clean ccache
    if [ -d "${HOME}/.ccache" ]; then
        print_status "Cleaning ccache..."
        rm -rf "${HOME}/.ccache"
    fi
    if [ -d "/root/.ccache" ]; then
        rm -rf "/root/.ccache"
    fi

    # Clean buildroot host directory (large, can be rebuilt)
    if [ -d "${BUILDROOT_DIR}/output/host" ]; then
        local HOST_SIZE=$(du -sm "${BUILDROOT_DIR}/output/host" 2>/dev/null | cut -f1)
        if [ "${HOST_SIZE:-0}" -gt 2000 ]; then
            print_status "Cleaning buildroot host directory (${HOST_SIZE}MB)..."
            rm -rf "${BUILDROOT_DIR}/output/host"
        fi
    fi

    # Show disk usage after
    echo ""
    print_status "Disk usage after cleanup:"
    df -h / 2>/dev/null | head -2

    print_status "Cleanup complete!"
}

distclean_build() {
    print_status "Full clean (distclean)..."

    if [ -d "${BUILDROOT_DIR}" ]; then
        cd "${BUILDROOT_DIR}"
        make distclean
    fi

    print_status "Distclean complete!"
}

install_global() {
    print_status "Installing straturaos command globally..."

    local INSTALL_PATH="/usr/local/bin/straturaos"
    local SCRIPT_PATH="${SCRIPT_DIR}/build.sh"

    if [ -L "${INSTALL_PATH}" ] || [ -f "${INSTALL_PATH}" ]; then
        rm -f "${INSTALL_PATH}"
    fi

    ln -s "${SCRIPT_PATH}" "${INSTALL_PATH}"
    chmod +x "${SCRIPT_PATH}"

    print_status "Installed! You can now run 'straturaos' from anywhere."
    echo ""
    echo "Usage: straturaos [command]"
    echo ""
    echo "Examples:"
    echo "  straturaos build"
    echo "  straturaos export"
    echo "  straturaos release"
}

uninstall_global() {
    print_status "Removing straturaos command..."

    local INSTALL_PATH="/usr/local/bin/straturaos"

    if [ -L "${INSTALL_PATH}" ] || [ -f "${INSTALL_PATH}" ]; then
        rm -f "${INSTALL_PATH}"
        print_status "Uninstalled successfully."
    else
        print_warning "straturaos command not found in ${INSTALL_PATH}"
    fi
}

package_images() {
    local ARCH=$(detect_arch)
    local VARIANT=$(detect_variant)
    local RELEASE_VERSION_DIR="${RELEASE_DIR}/${VERSION}"
    local RELEASE_ARCH_DIR="${RELEASE_VERSION_DIR}/${ARCH}"
    local RELEASE_ISO_DIR="${RELEASE_VERSION_DIR}/iso"
    local RELEASE_DOCKER_DIR="${RELEASE_VERSION_DIR}/docker"
    local NAME_PREFIX="straturaos-${VERSION}-${VARIANT}-${ARCH}-${BUILD_DATE}-${BUILD_TIME}"

    print_status "Packaging images..."
    print_status "  Version: ${VERSION}"
    print_status "  Variant: ${VARIANT}"
    print_status "  Arch: ${ARCH}"

    # Check for any built images
    if [ ! -f "${IMAGES_DIR}/sdcard.img" ] && \
       [ ! -f "${IMAGES_DIR}/rootfs.ext4" ] && \
       [ ! -f "${IMAGES_DIR}/rootfs.squashfs" ] && \
       [ ! -f "${IMAGES_DIR}/rootfs.tar" ] && \
       [ ! -f "${IMAGES_DIR}/bzImage" ]; then
        print_error "No images found. Run './build.sh build' first."
        exit 1
    fi

    # Create release directories
    mkdir -p "${RELEASE_DOCKER_DIR}"

    # Only clean up directories for the current build target (not other architectures)
    print_status "Removing old release files for ${ARCH}..."

    # Process SD card image (RPi/arm64 builds only)
    if [ -f "${IMAGES_DIR}/sdcard.img" ]; then
        mkdir -p "${RELEASE_ARCH_DIR}"
        rm -f "${RELEASE_ARCH_DIR}"/straturaos-*.img 2>/dev/null || true
        rm -f "${RELEASE_ARCH_DIR}"/straturaos-*.img.sign 2>/dev/null || true
        rm -f "${RELEASE_ARCH_DIR}"/SHA512SUMS* 2>/dev/null || true
        # Only clean arm64 docker tarballs (not amd64)
        rm -f "${RELEASE_DOCKER_DIR}"/straturaos-*-arm64-*.tar 2>/dev/null || true
        rm -f "${RELEASE_DOCKER_DIR}"/straturaos-*-arm64-*.tar.sign 2>/dev/null || true
        local IMG_NAME="${NAME_PREFIX}.img"
        mv "${IMAGES_DIR}/sdcard.img" "${RELEASE_ARCH_DIR}/${IMG_NAME}"
        rm -f "${IMAGES_DIR}/sdcard.img.sha256" 2>/dev/null
        print_status "Created: ${ARCH}/${IMG_NAME}"
    fi

    # Process x86_64/amd64 builds - clean only amd64 artifacts
    if [ "${ARCH}" = "amd64" ]; then
        # Clean old ISO files (only for amd64)
        rm -f "${RELEASE_ISO_DIR}"/straturaos-*.iso 2>/dev/null || true
        rm -f "${RELEASE_ISO_DIR}"/straturaos-*.iso.sign 2>/dev/null || true
        rm -f "${RELEASE_ISO_DIR}"/SHA512SUMS* 2>/dev/null || true
        # Only clean amd64 docker tarballs (not arm64)
        rm -f "${RELEASE_DOCKER_DIR}"/straturaos-*-amd64-*.tar 2>/dev/null || true
        rm -f "${RELEASE_DOCKER_DIR}"/straturaos-*-amd64-*.tar.sign 2>/dev/null || true
    fi

    # Create Docker tarball in docker/ directory
    local TAR_NAME="${NAME_PREFIX}.tar"
    if [ -f "${IMAGES_DIR}/rootfs.tar" ]; then
        mv "${IMAGES_DIR}/rootfs.tar" "${RELEASE_DOCKER_DIR}/${TAR_NAME}"
        print_status "Created: docker/${TAR_NAME}"
    elif [ -f "${IMAGES_DIR}/rootfs.ext4" ]; then
        local MOUNT_DIR="${STRATURAOS_TMP}/straturaos-rootfs-$$"
        mkdir -p "${MOUNT_DIR}"
        print_status "Extracting rootfs to tar..."
        mount -o loop,ro "${IMAGES_DIR}/rootfs.ext4" "${MOUNT_DIR}"
        tar -C "${MOUNT_DIR}" -cf "${RELEASE_DOCKER_DIR}/${TAR_NAME}" .
        umount "${MOUNT_DIR}"
        rmdir "${MOUNT_DIR}"
        print_status "Created: docker/${TAR_NAME}"
    fi

    # Generate SHA512SUMS for arch directory
    if ls "${RELEASE_ARCH_DIR}"/straturaos-* 1>/dev/null 2>&1; then
        print_status "Generating checksums for ${ARCH}/..."
        cd "${RELEASE_ARCH_DIR}"
        sha512sum straturaos-${VERSION}-* > SHA512SUMS 2>/dev/null || true
        if command -v gpg &> /dev/null && gpg --list-secret-keys 2>/dev/null | grep -q "sec"; then
            for file in straturaos-${VERSION}-*; do
                if [ -f "$file" ] && [[ ! "$file" =~ \.sign$ ]]; then
                    gpg --yes --detach-sign -o "${file}.sign" "$file" 2>/dev/null || true
                fi
            done
            gpg --yes --detach-sign -o "SHA512SUMS.sign" SHA512SUMS 2>/dev/null || true
        fi
    fi

    # Generate SHA512SUMS for docker directory
    if ls "${RELEASE_DOCKER_DIR}"/straturaos-* 1>/dev/null 2>&1; then
        print_status "Generating checksums for docker/..."
        cd "${RELEASE_DOCKER_DIR}"
        sha512sum straturaos-${VERSION}-* > SHA512SUMS 2>/dev/null || true
        if command -v gpg &> /dev/null && gpg --list-secret-keys 2>/dev/null | grep -q "sec"; then
            for file in straturaos-${VERSION}-*; do
                if [ -f "$file" ] && [[ ! "$file" =~ \.sign$ ]]; then
                    gpg --yes --detach-sign -o "${file}.sign" "$file" 2>/dev/null || true
                fi
            done
            gpg --yes --detach-sign -o "SHA512SUMS.sign" SHA512SUMS 2>/dev/null || true
        fi
    fi

    print_status "Package complete!"
}

create_docker() {
    print_status "Creating Docker image..."

    local ARCH=$(detect_arch)
    local RELEASE_VERSION_DIR="${RELEASE_DIR}/${VERSION}"
    local RELEASE_DOCKER_DIR="${RELEASE_VERSION_DIR}/docker"

    # Find the Docker tarball for the CURRENT architecture only
    local DOCKER_TAR=""
    if ls "${RELEASE_DOCKER_DIR}"/straturaos-*-${ARCH}-*.tar 1>/dev/null 2>&1; then
        DOCKER_TAR=$(ls -t "${RELEASE_DOCKER_DIR}"/straturaos-*-${ARCH}-*.tar | head -1)
    elif [ -f "${IMAGES_DIR}/rootfs.tar" ]; then
        DOCKER_TAR="${IMAGES_DIR}/rootfs.tar"
    fi

    if [ -z "${DOCKER_TAR}" ]; then
        print_warning "No Docker tarball found for ${ARCH}. Skipping Docker image creation."
        return 0
    fi

    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed. Skipping Docker image creation."
        return 0
    fi

    # Use architecture-specific tags to avoid overwriting
    local TAG="${VERSION}-${ARCH}-${BUILD_DATE}"
    docker import "${DOCKER_TAR}" "straturaos:${TAG}" > /dev/null
    docker tag "straturaos:${TAG}" "straturaos:latest-${ARCH}"

    print_status "Created: straturaos:${TAG}"
    print_status "Created: straturaos:latest-${ARCH}"
}

create_iso() {
    local ARCH=$(detect_arch)
    local VARIANT=$(detect_variant)
    local RELEASE_VERSION_DIR="${RELEASE_DIR}/${VERSION}"
    local RELEASE_ISO_DIR="${RELEASE_VERSION_DIR}/iso"
    local NAME_PREFIX="straturaos-${VERSION}-${VARIANT}-${ARCH}-${BUILD_DATE}-${BUILD_TIME}"
    local ISO_NAME="${NAME_PREFIX}.iso"

    # ISO creation only for x86_64/amd64 builds
    if [ "${ARCH}" != "amd64" ]; then
        print_warning "ISO creation only supported for x86_64 builds"
        return 0
    fi

    print_status "Creating bootable ISO..."

    # Check for required tools
    if ! command -v xorriso &> /dev/null; then
        print_warning "xorriso not found. Install with: apt-get install xorriso"
        print_warning "Skipping ISO creation"
        return 0
    fi

    # Check for kernel and rootfs
    if [ ! -f "${IMAGES_DIR}/bzImage" ] && [ ! -f "${IMAGES_DIR}/vmlinuz" ]; then
        print_error "Kernel image not found"
        return 1
    fi

    if [ ! -f "${IMAGES_DIR}/rootfs.ext4" ] && [ ! -f "${IMAGES_DIR}/rootfs.squashfs" ]; then
        print_error "Root filesystem not found"
        return 1
    fi

    # Create ISO staging directory
    local ISO_DIR="${STRATURAOS_TMP}/straturaos-iso-$$"
    mkdir -p "${ISO_DIR}/boot/grub"
    mkdir -p "${ISO_DIR}/EFI/BOOT"
    mkdir -p "${ISO_DIR}/live"

    # Copy kernel
    if [ -f "${IMAGES_DIR}/bzImage" ]; then
        cp "${IMAGES_DIR}/bzImage" "${ISO_DIR}/boot/vmlinuz"
    elif [ -f "${IMAGES_DIR}/vmlinuz" ]; then
        cp "${IMAGES_DIR}/vmlinuz" "${ISO_DIR}/boot/vmlinuz"
    fi

    # Copy rootfs
    if [ -f "${IMAGES_DIR}/rootfs.squashfs" ]; then
        cp "${IMAGES_DIR}/rootfs.squashfs" "${ISO_DIR}/live/filesystem.squashfs"
    elif [ -f "${IMAGES_DIR}/rootfs.ext4" ]; then
        cp "${IMAGES_DIR}/rootfs.ext4" "${ISO_DIR}/live/filesystem.ext4"
    fi

    # Create GRUB config for BIOS boot
    cat > "${ISO_DIR}/boot/grub/grub.cfg" << 'GRUBCFG'
set timeout=5
set default=0

menuentry "StraturaOS" {
    linux /boot/vmlinuz root=/dev/sr0 rootfstype=iso9660 console=tty0 console=ttyS0,115200
    boot
}

menuentry "StraturaOS (Serial Console)" {
    linux /boot/vmlinuz root=/dev/sr0 rootfstype=iso9660 console=ttyS0,115200
    boot
}
GRUBCFG

    # Create EFI bootloader if grub-mkimage is available
    if command -v grub-mkstandalone &> /dev/null; then
        grub-mkstandalone \
            --format=x86_64-efi \
            --output="${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" \
            --locales="" \
            --fonts="" \
            "boot/grub/grub.cfg=${ISO_DIR}/boot/grub/grub.cfg" 2>/dev/null || true
    fi

    # Copy EFI bootloader from build output if available
    if [ -d "${IMAGES_DIR}/EFI/BOOT" ]; then
        cp -a "${IMAGES_DIR}/EFI/BOOT/"* "${ISO_DIR}/EFI/BOOT/" 2>/dev/null || true
    elif [ -f "${IMAGES_DIR}/efi-part/EFI/BOOT/bootx64.efi" ]; then
        cp "${IMAGES_DIR}/efi-part/EFI/BOOT/bootx64.efi" "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI"
    fi

    # Create the ISO in iso/ directory
    mkdir -p "${RELEASE_ISO_DIR}"

    print_status "Running xorriso..."

    # Simple ISO creation with EFI boot support
    if [ -f "${ISO_DIR}/EFI/BOOT/BOOTX64.EFI" ] || [ -f "${ISO_DIR}/EFI/BOOT/bootx64.efi" ]; then
        # EFI bootable ISO
        xorriso -as mkisofs \
            -o "${RELEASE_ISO_DIR}/${ISO_NAME}" \
            -V "STRATURAOS" \
            -J -R -l \
            -eltorito-alt-boot \
            -e EFI/BOOT/BOOTX64.EFI \
            -no-emul-boot \
            "${ISO_DIR}"
        ISO_RESULT=$?
    else
        # Basic ISO without EFI
        print_warning "No EFI bootloader found, creating basic ISO"
        xorriso -as mkisofs \
            -o "${RELEASE_ISO_DIR}/${ISO_NAME}" \
            -V "STRATURAOS" \
            -J -R -l \
            "${ISO_DIR}"
        ISO_RESULT=$?
    fi

    # Cleanup staging
    rm -rf "${ISO_DIR}"

    if [ ${ISO_RESULT} -eq 0 ] && [ -f "${RELEASE_ISO_DIR}/${ISO_NAME}" ]; then
        print_status "Created: iso/${ISO_NAME}"
        # Generate checksums and signatures for ISO
        cd "${RELEASE_ISO_DIR}"
        sha512sum straturaos-${VERSION}-* > SHA512SUMS 2>/dev/null || true
        if command -v gpg &> /dev/null && gpg --list-secret-keys 2>/dev/null | grep -q "sec"; then
            gpg --yes --detach-sign -o "${ISO_NAME}.sign" "${ISO_NAME}" 2>/dev/null || true
            gpg --yes --detach-sign -o "SHA512SUMS.sign" SHA512SUMS 2>/dev/null || true
        fi
    else
        print_error "ISO creation failed with exit code ${ISO_RESULT}"
        return 1
    fi
}

export_artifacts() {
    print_status "Exporting artifacts..."

    package_images

    # Create ISO for x86_64 builds
    local ARCH=$(detect_arch)
    if [ "${ARCH}" = "amd64" ]; then
        create_iso
    fi

    # Create Docker image if Docker is available
    if command -v docker &> /dev/null; then
        create_docker
    fi

    # Show all output files
    local ARCH=$(detect_arch)
    local RELEASE_VERSION_DIR="${RELEASE_DIR}/${VERSION}"
    local RELEASE_ARCH_DIR="${RELEASE_VERSION_DIR}/${ARCH}"
    local RELEASE_ISO_DIR="${RELEASE_VERSION_DIR}/iso"
    local RELEASE_DOCKER_DIR="${RELEASE_VERSION_DIR}/docker"

    echo ""
    echo "=========================================="
    echo "Release directory: ${RELEASE_DIR}/"
    echo ""

    # Show directory tree
    if command -v tree &> /dev/null; then
        tree -h "${RELEASE_DIR}" 2>/dev/null || ls -lahR "${RELEASE_DIR}"
    else
        echo "${VERSION}/"

        # Show arch directory
        if [ -d "${RELEASE_ARCH_DIR}" ] && ls "${RELEASE_ARCH_DIR}"/* 1>/dev/null 2>&1; then
            echo "  ${ARCH}/"
            ls -lh "${RELEASE_ARCH_DIR}"/ 2>/dev/null | tail -n +2 | while read line; do
                echo "    $line"
            done
        fi

        # Show docker directory
        if [ -d "${RELEASE_DOCKER_DIR}" ] && ls "${RELEASE_DOCKER_DIR}"/* 1>/dev/null 2>&1; then
            echo "  docker/"
            ls -lh "${RELEASE_DOCKER_DIR}"/ 2>/dev/null | tail -n +2 | while read line; do
                echo "    $line"
            done
        fi

        # Show iso directory
        if [ -d "${RELEASE_ISO_DIR}" ] && ls "${RELEASE_ISO_DIR}"/* 1>/dev/null 2>&1; then
            echo "  iso/"
            ls -lh "${RELEASE_ISO_DIR}"/ 2>/dev/null | tail -n +2 | while read line; do
                echo "    $line"
            done
        fi
    fi

    if command -v docker &> /dev/null; then
        echo ""
        echo "Docker images:"
        docker images --format "  {{.Repository}}:{{.Tag}}\t{{.Size}}" | grep straturaos || true
    fi
    echo "=========================================="

    print_status "Export complete!"
}

do_release() {
    print_status "Starting full release build..."

    build_image
    export_artifacts

    print_status "Release complete!"
}

show_help() {
    echo "StraturaOS Build System"
    echo ""
    echo "Usage: straturaos [command]"
    echo ""
    echo "Commands:"
    echo "  setup          Install dependencies and clone Buildroot"
    echo "  build [target] Build StraturaOS (creates ISO, SD card, Docker)"
    echo "  clean          Clean build directory (next build is fresh)"
    echo "  help           Show this help message"
    echo ""
    echo "Build targets:"
    echo "  iso            x86_64 - creates ISO + Docker image (incremental)"
    echo "  rpi5           ARM64 - creates SD card image + Docker image (incremental)"
    echo "  all            Build both targets (clean build, default)"
    echo ""
    echo "Quick start:"
    echo "  straturaos setup       # First time only"
    echo "  straturaos build       # Build all targets (clean)"
    echo "  straturaos build iso   # Build x86_64 only (incremental)"
    echo "  straturaos build rpi5  # Build RPi5 only (incremental)"
    echo ""
    echo "Docker images created:"
    echo "  straturaos:latest-arm64   # RPi5 build"
    echo "  straturaos:latest-amd64   # x86_64 build"
}

# Main
case "${1:-help}" in
    setup)
        install_dependencies
        setup_buildroot
        ;;
    build)
        # "all" always does clean (required for arch switch), single targets are incremental
        if [ "${2:-all}" = "all" ]; then
            build_image "all" "clean"
        else
            build_image "${2}" "no"
        fi
        ;;
    clean)
        clean_build
        ;;
    help|--help|-h)
        show_help
        ;;
    # Hidden/advanced commands (still work, not shown in help)
    menuconfig)
        run_menuconfig
        ;;
    distclean)
        distclean_build
        ;;
    install)
        install_global
        ;;
    uninstall)
        uninstall_global
        ;;
    # Legacy commands (kept for backwards compatibility)
    deps)
        install_dependencies
        ;;
    config)
        configure_build "${2:-rpi5}"
        ;;
    rebuild)
        build_image "${2:-all}" "clean"
        ;;
    package)
        package_images
        ;;
    docker)
        create_docker
        ;;
    iso)
        create_iso
        ;;
    export)
        export_artifacts
        ;;
    release)
        do_release
        ;;
    cleanup)
        cleanup_old_artifacts 1
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
