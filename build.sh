#!/bin/bash
# StraturaOS Build Script
# Usage: ./build.sh [command]
#
# Commands:
#   setup     - Clone Buildroot and setup environment
#   config    - Configure build (menuconfig)
#   build     - Build the image
#   package   - Create dated images and rootfs.tar
#   docker    - Create Docker image from rootfs
#   release   - Build + package + docker
#   clean     - Clean build directory
#   distclean - Full clean (reset everything)

set -e

# Resolve symlinks to get the real script location
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
    DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

BUILDROOT_DIR="${SCRIPT_DIR}/../buildroot"

# EXTERNAL_DIR: use subdirectory if exists, otherwise use SCRIPT_DIR itself
if [ -d "${SCRIPT_DIR}/buildroot-external" ]; then
    EXTERNAL_DIR="${SCRIPT_DIR}/buildroot-external"
else
    EXTERNAL_DIR="${SCRIPT_DIR}"
fi
BUILD_DIR="${BUILDROOT_DIR}/output"
IMAGES_DIR="${BUILD_DIR}/images"
BUILD_DATE=$(date +%Y%m%d)

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

    local deps="git make gcc g++ ncurses-dev wget cpio unzip rsync bc libssl-dev"
    local missing=""

    for dep in build-essential libncurses5-dev; do
        if ! dpkg -l | grep -q "^ii  ${dep}"; then
            missing="${missing} ${dep}"
        fi
    done

    if [ -n "${missing}" ]; then
        print_warning "Missing packages:${missing}"
        echo "Install with: sudo apt-get install -y${missing}"
    fi
}

setup_buildroot() {
    print_status "Setting up Buildroot..."

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_status "Cloning Buildroot..."
        git clone https://github.com/buildroot/buildroot "${BUILDROOT_DIR}"
        cd "${BUILDROOT_DIR}"
        # Use a stable release
        git checkout 2024.02.1
    else
        print_status "Buildroot already exists at ${BUILDROOT_DIR}"
    fi

    print_status "Setup complete!"
    echo ""
    echo "Next steps:"
    echo "  1. ./build.sh config  - Configure the build"
    echo "  2. ./build.sh build   - Build the image"
}

configure_build() {
    print_status "Configuring StraturaOS build..."

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_error "Buildroot not found. Run './build.sh setup' first."
        exit 1
    fi

    cd "${BUILDROOT_DIR}"

    # Load StraturaOS defconfig
    make BR2_EXTERNAL="${EXTERNAL_DIR}" straturaos_defconfig

    print_status "Configuration loaded!"
    echo ""
    echo "Run 'make menuconfig' in ${BUILDROOT_DIR} to customize"
    echo "Or run './build.sh build' to build with default config"
}

run_menuconfig() {
    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_error "Buildroot not found. Run './build.sh setup' first."
        exit 1
    fi

    cd "${BUILDROOT_DIR}"
    make BR2_EXTERNAL="${EXTERNAL_DIR}" menuconfig
}

build_image() {
    print_status "Building StraturaOS..."

    if [ ! -d "${BUILDROOT_DIR}" ]; then
        print_error "Buildroot not found. Run './build.sh setup' first."
        exit 1
    fi

    if [ ! -f "${BUILDROOT_DIR}/.config" ]; then
        print_status "No config found, loading defconfig..."
        configure_build
    fi

    # Cleanup old artifacts before building
    cleanup_old_artifacts 2

    cd "${BUILDROOT_DIR}"

    # Build with all available cores
    make BR2_EXTERNAL="${EXTERNAL_DIR}" -j$(nproc)

    # Auto-export artifacts with timestamp
    export_artifacts
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
    local KEEP_COUNT=${1:-2}
    print_status "Cleaning up old artifacts (keeping last ${KEEP_COUNT})..."

    # Cleanup old SD card images
    if [ -d "${IMAGES_DIR}" ]; then
        local IMG_COUNT=$(ls -1 "${IMAGES_DIR}"/straturaos-sdcard-*.img 2>/dev/null | wc -l)
        if [ "${IMG_COUNT}" -gt "${KEEP_COUNT}" ]; then
            print_status "Removing old SD card images..."
            ls -1t "${IMAGES_DIR}"/straturaos-sdcard-*.img 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read img; do
                echo "  Removing: $(basename ${img})"
                rm -f "${img}" "${img}.sha256"
            done
        fi

        # Cleanup old Docker tarballs
        local TAR_COUNT=$(ls -1 "${IMAGES_DIR}"/straturaos-docker-*.tar 2>/dev/null | wc -l)
        if [ "${TAR_COUNT}" -gt "${KEEP_COUNT}" ]; then
            print_status "Removing old Docker tarballs..."
            ls -1t "${IMAGES_DIR}"/straturaos-docker-*.tar 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read tar; do
                echo "  Removing: $(basename ${tar})"
                rm -f "${tar}"
            done
        fi
    fi

    # Cleanup old Docker images if Docker is available
    if command -v docker &> /dev/null; then
        local DOCKER_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' | grep '^straturaos:' | grep -v ':latest' | sort -r)
        local DOCKER_COUNT=$(echo "${DOCKER_IMAGES}" | grep -c '^straturaos:' || echo 0)

        if [ "${DOCKER_COUNT}" -gt "${KEEP_COUNT}" ]; then
            print_status "Removing old Docker images..."
            echo "${DOCKER_IMAGES}" | tail -n +$((KEEP_COUNT + 1)) | while read img; do
                echo "  Removing: ${img}"
                docker rmi "${img}" 2>/dev/null || true
            done
        fi
    fi

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
    print_status "Packaging images with date: ${BUILD_DATE}..."

    # Check for any built images
    if [ ! -f "${IMAGES_DIR}/sdcard.img" ] && [ ! -f "${IMAGES_DIR}/rootfs.ext4" ]; then
        print_error "No images found. Run './build.sh build' first."
        exit 1
    fi

    # Rename SD card image with timestamp
    if [ -f "${IMAGES_DIR}/sdcard.img" ]; then
        mv "${IMAGES_DIR}/sdcard.img" "${IMAGES_DIR}/straturaos-sdcard-${BUILD_DATE}.img"
        # Update checksum file if exists
        if [ -f "${IMAGES_DIR}/sdcard.img.sha256" ]; then
            sed -i "s/sdcard.img/straturaos-sdcard-${BUILD_DATE}.img/" "${IMAGES_DIR}/sdcard.img.sha256"
            mv "${IMAGES_DIR}/sdcard.img.sha256" "${IMAGES_DIR}/straturaos-sdcard-${BUILD_DATE}.img.sha256"
        fi
        print_status "Created: straturaos-sdcard-${BUILD_DATE}.img"
    else
        print_warning "No sdcard.img found (genimage may not have run)"
    fi

    # Create Docker tarball with timestamp
    if [ -f "${IMAGES_DIR}/rootfs.tar" ]; then
        mv "${IMAGES_DIR}/rootfs.tar" "${IMAGES_DIR}/straturaos-docker-${BUILD_DATE}.tar"
        print_status "Created: straturaos-docker-${BUILD_DATE}.tar"
    elif [ -f "${IMAGES_DIR}/rootfs.ext4" ]; then
        local MOUNT_DIR="/tmp/straturaos-rootfs-$$"
        mkdir -p "${MOUNT_DIR}"

        print_status "Extracting rootfs to tar..."
        mount -o loop,ro "${IMAGES_DIR}/rootfs.ext4" "${MOUNT_DIR}"
        tar -C "${MOUNT_DIR}" -cf "${IMAGES_DIR}/straturaos-docker-${BUILD_DATE}.tar" .
        umount "${MOUNT_DIR}"
        rmdir "${MOUNT_DIR}"

        print_status "Created: straturaos-docker-${BUILD_DATE}.tar"
    else
        print_warning "rootfs.ext4 not found, skipping Docker tarball creation"
    fi

    print_status "Package complete!"
}

create_docker() {
    print_status "Creating Docker image..."

    # Find the Docker tarball (with or without date)
    local DOCKER_TAR=""
    if ls "${IMAGES_DIR}"/straturaos-docker-*.tar 1>/dev/null 2>&1; then
        DOCKER_TAR=$(ls -t "${IMAGES_DIR}"/straturaos-docker-*.tar | head -1)
    elif [ -f "${IMAGES_DIR}/rootfs.tar" ]; then
        DOCKER_TAR="${IMAGES_DIR}/rootfs.tar"
    fi

    if [ -z "${DOCKER_TAR}" ]; then
        print_error "No Docker tarball found. Run 'straturaos export' first."
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Install Docker first."
        exit 1
    fi

    docker import "${DOCKER_TAR}" "straturaos:${BUILD_DATE}" > /dev/null
    docker tag "straturaos:${BUILD_DATE}" straturaos:latest

    print_status "Created: straturaos:${BUILD_DATE}"
    print_status "Created: straturaos:latest"
}

export_artifacts() {
    print_status "Exporting artifacts..."

    package_images

    # Create Docker image if Docker is available
    if command -v docker &> /dev/null; then
        create_docker
    fi

    # Show all output files
    echo ""
    echo "=========================================="
    echo "Output files:"
    ls -lh "${IMAGES_DIR}"/straturaos-sdcard-${BUILD_DATE}.img 2>/dev/null || true
    ls -lh "${IMAGES_DIR}"/straturaos-docker-${BUILD_DATE}.tar 2>/dev/null || true
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
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  setup      Clone Buildroot and setup environment"
    echo "  config     Load StraturaOS defconfig"
    echo "  menuconfig Interactive configuration menu"
    echo "  build      Build the image"
    echo "  package    Create dated sdcard.img and rootfs.tar"
    echo "  docker     Create Docker image from rootfs"
    echo "  export     Package + docker (no rebuild)"
    echo "  release    Build + package + docker (full release)"
    echo "  clean      Clean build directory"
    echo "  cleanup    Remove old artifacts (keeps last 2)"
    echo "  distclean  Full clean (reset everything)"
    echo "  install    Install 'straturaos' command globally"
    echo "  uninstall  Remove global 'straturaos' command"
    echo "  help       Show this help message"
    echo ""
    echo "Quick start:"
    echo "  ./build.sh setup"
    echo "  ./build.sh build"
    echo ""
    echo "Full release:"
    echo "  ./build.sh release"
}

# Main
case "${1:-help}" in
    setup)
        check_dependencies
        setup_buildroot
        ;;
    config)
        configure_build
        ;;
    menuconfig)
        run_menuconfig
        ;;
    build)
        build_image
        ;;
    package)
        package_images
        ;;
    docker)
        create_docker
        ;;
    export)
        export_artifacts
        ;;
    release)
        do_release
        ;;
    clean)
        clean_build
        ;;
    cleanup)
        cleanup_old_artifacts 2
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
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
