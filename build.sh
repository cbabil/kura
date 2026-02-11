#!/bin/bash
# StraturaOS Build Script (Debian)
# Usage: ./build.sh [command]
#
# Commands:
#   setup            - Install host dependencies for Debian builds
#   build {target}   - Build StraturaOS image (rpi5|iso|docker|all)
#   clean            - Remove build rootfs and temp files
#   help             - Show this help message

set -euo pipefail

# Resolve symlinks to get the real script location
SOURCE="${BASH_SOURCE[0]}"
while [ -L "${SOURCE}" ]; do
    DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"
    SOURCE="$(readlink "${SOURCE}")"
    [[ ${SOURCE} != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
SCRIPT_DIR="$(cd -P "$(dirname "${SOURCE}")" && pwd)"

PROJECT_DIR="${SCRIPT_DIR}"

# ============================================================================
# .env loading
# ============================================================================

if [ -f "${PROJECT_DIR}/.env" ]; then
    # shellcheck disable=SC1091
    source "${PROJECT_DIR}/.env"
elif [ -f "${PROJECT_DIR}/.env.example" ]; then
    echo -e "\033[1;33m[WARNING]\033[0m No .env found. Copy the template: cp .env.example .env"
fi

EXPECTED_CONF_VERSION="2"

STRATURAOS_CONF_VERSION="${STRATURAOS_CONF_VERSION:-${EXPECTED_CONF_VERSION}}"

if [ "${STRATURAOS_CONF_VERSION}" != "${EXPECTED_CONF_VERSION}" ]; then
    echo -e "\033[1;33m[WARNING]\033[0m .env version mismatch (have: ${STRATURAOS_CONF_VERSION}, expected: ${EXPECTED_CONF_VERSION})"
    echo -e "\033[1;33m[WARNING]\033[0m Your .env may need updating. See .env.example for current variables."
fi

# ============================================================================
# Defaults
# ============================================================================

STRATURAOS_DEBIAN_SUITE="${STRATURAOS_DEBIAN_SUITE:-trixie}"
STRATURAOS_DEBIAN_MIRROR="${STRATURAOS_DEBIAN_MIRROR:-http://deb.debian.org/debian}"
STRATURAOS_CROSS_BUILD="${STRATURAOS_CROSS_BUILD:-auto}"
STRATURAOS_PARALLEL_JOBS="${STRATURAOS_PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 1)}"
STRATURAOS_NAME="${STRATURAOS_NAME:-StraturaOS}"
STRATURAOS_VERSION="${STRATURAOS_VERSION:-2.0}"
STRATURAOS_HOSTNAME="${STRATURAOS_HOSTNAME:-straturaos}"
STRATURAOS_ROOT_PASSWD="${STRATURAOS_ROOT_PASSWD:-stratura}"
STRATURAOS_ISSUE="${STRATURAOS_ISSUE:-Welcome to StraturaOS}"
STRATURAOS_DHCP_INTERFACE="${STRATURAOS_DHCP_INTERFACE:-eth0}"
STRATURAOS_ROOTFS_SIZE="${STRATURAOS_ROOTFS_SIZE:-2G}"
STRATURAOS_TMP="${STRATURAOS_TMP:-/home/straturaos/tmp}"

export STRATURAOS_CONF_VERSION STRATURAOS_DEBIAN_SUITE STRATURAOS_DEBIAN_MIRROR
export STRATURAOS_CROSS_BUILD STRATURAOS_PARALLEL_JOBS STRATURAOS_NAME STRATURAOS_VERSION
export STRATURAOS_HOSTNAME STRATURAOS_ROOT_PASSWD STRATURAOS_ISSUE
export STRATURAOS_DHCP_INTERFACE STRATURAOS_ROOTFS_SIZE STRATURAOS_TMP

mkdir -p "${STRATURAOS_TMP}" 2>/dev/null || true

# Shared paths
RELEASE_DIR="${PROJECT_DIR}/release"
PACKAGES_DIR="${PROJECT_DIR}/packages"
SCRIPTS_DIR="${PROJECT_DIR}/scripts"
OVERLAY_DIR="${PROJECT_DIR}/overlay"
CONFIG_DIR="${PROJECT_DIR}/config"
VERSION="${STRATURAOS_VERSION}"
BUILD_DATE=$(date +%Y%m%d)
# Build number (auto-incremented, zero-padded, stored in .build-number)
BUILD_NUMBER_FILE="${PROJECT_DIR}/.build-number"
if [ -f "${BUILD_NUMBER_FILE}" ]; then
    STRATURAOS_BUILD_NUMBER=$(cat "${BUILD_NUMBER_FILE}")
else
    STRATURAOS_BUILD_NUMBER=0
fi
STRATURAOS_BUILD_NUMBER=$((STRATURAOS_BUILD_NUMBER + 1))
echo "${STRATURAOS_BUILD_NUMBER}" > "${BUILD_NUMBER_FILE}"
STRATURAOS_BUILD_SEQ=$(printf "%04d" "${STRATURAOS_BUILD_NUMBER}")
export BUILD_DATE STRATURAOS_BUILD_SEQ

# ============================================================================
# Color output helpers
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[StraturaOS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

CYAN='\033[0;36m'
BOLD='\033[1m'

# print_build_summary -- show a nice summary of build artifacts
print_build_summary() {
    local TARGET="$1"
    local BUILD_START="${2:-}"
    local TARGET_DIR

    case "${TARGET}" in
        rpi5)   TARGET_DIR="${RELEASE_DIR}/${VERSION}/arm64" ;;
        iso)    TARGET_DIR="${RELEASE_DIR}/${VERSION}/iso" ;;
        docker) TARGET_DIR="${RELEASE_DIR}/${VERSION}/docker" ;;
        *)      return 0 ;;
    esac

    [ ! -d "${TARGET_DIR}" ] && return 0

    local TARGET_LABEL
    case "${TARGET}" in
        rpi5)   TARGET_LABEL="RPi5 SD Card Image" ;;
        iso)    TARGET_LABEL="x86_64 Hybrid ISO" ;;
        docker) TARGET_LABEL="Docker Rootfs Tarball" ;;
    esac

    local DURATION=""
    if [ -n "${BUILD_START}" ]; then
        local ELAPSED=$(( $(date +%s) - BUILD_START ))
        local MINS=$(( ELAPSED / 60 ))
        local SECS=$(( ELAPSED % 60 ))
        DURATION=" (${MINS}m ${SECS}s)"
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Build Complete: ${TARGET_LABEL}${NC}${DURATION}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"

    for file in "${TARGET_DIR}"/straturaos-"${VERSION}"-*; do
        [ ! -f "${file}" ] && continue
        [[ "${file}" =~ \.sign$ ]] && continue
        [[ "$(basename "${file}")" = "SHA512SUMS" ]] && continue
        local SIZE
        SIZE=$(du -h "${file}" | cut -f1)
        echo -e "${GREEN}║${NC}  ${CYAN}$(basename "${file}")${NC}"
        echo -e "${GREEN}║${NC}    Size: ${BOLD}${SIZE}${NC}"
        echo -e "${GREEN}║${NC}    Path: ${TARGET_DIR}/"
    done

    if [ -f "${TARGET_DIR}/SHA512SUMS" ]; then
        echo -e "${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}  ${BOLD}SHA512SUMS:${NC}"
        while IFS= read -r line; do
            echo -e "${GREEN}║${NC}    ${line}"
        done < "${TARGET_DIR}/SHA512SUMS"
    fi

    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# ============================================================================
# setup_host -- install host build dependencies
# ============================================================================

setup_host() {
    print_status "Installing host build dependencies..."

    local REQUIRED_PKGS="
        mmdebstrap
        qemu-user-static
        binfmt-support
        debootstrap
        rsync
        xorriso
        grub-pc-bin
        grub-efi-amd64-bin
        mtools
        dosfstools
        squashfs-tools
        e2fsprogs
        gdisk
        python3
        python3-pytest
        shellcheck
        docker.io
        containerd
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
        # shellcheck disable=SC2086
        apt-get install -y ${missing}
        print_status "Host dependencies installed."
    else
        print_status "All host dependencies are installed."
    fi
}

# ============================================================================
# bootstrap_rootfs -- create minimal Debian rootfs via mmdebstrap
# ============================================================================

bootstrap_rootfs() {
    local ROOTFS="$1"
    local ARCH="$2"

    local MMDEBSTRAP_OPTS=(
        --variant=minbase
        "--arch=${ARCH}"
        --quiet
    )

    # Cross-build detection
    local HOST_ARCH
    HOST_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    if [ "${ARCH}" != "${HOST_ARCH}" ]; then
        if [ "${STRATURAOS_CROSS_BUILD}" = "no" ]; then
            print_error "Cross-build required (host=${HOST_ARCH}, target=${ARCH}) but STRATURAOS_CROSS_BUILD=no"
            exit 1
        fi
        print_status "Cross-building: host=${HOST_ARCH}, target=${ARCH}"
    fi

    mmdebstrap "${MMDEBSTRAP_OPTS[@]}" \
        "${STRATURAOS_DEBIAN_SUITE}" "${ROOTFS}" "${STRATURAOS_DEBIAN_MIRROR}"

    print_status "Bootstrap complete."
}

# ============================================================================
# install_packages -- install Debian packages from package lists into rootfs
# ============================================================================

install_packages() {
    local ROOTFS="$1"
    local TARGET="$2"

    # Mount virtual filesystems for chroot
    mount_chroot "${ROOTFS}"

    # Read common package list
    local PACKAGES=""
    if [ -f "${CONFIG_DIR}/packages-common.list" ]; then
        PACKAGES=$(grep -v '^#' "${CONFIG_DIR}/packages-common.list" | grep -v '^$' | tr '\n' ' ')
    fi

    # Read target-specific package list
    local TARGET_LIST="${CONFIG_DIR}/packages-${TARGET}.list"
    if [ -f "${TARGET_LIST}" ]; then
        local TARGET_PKGS
        TARGET_PKGS=$(grep -v '^#' "${TARGET_LIST}" | grep -v '^$' | tr '\n' ' ')
        PACKAGES="${PACKAGES} ${TARGET_PKGS}"
    fi

    if [ -n "${PACKAGES}" ]; then
        # shellcheck disable=SC2086
        chroot "${ROOTFS}" apt-get update -qq 2>&1 | grep -v "^$" || true
        # shellcheck disable=SC2086
        chroot "${ROOTFS}" apt-get install -y -qq --no-install-recommends ${PACKAGES}
    fi

    umount_chroot "${ROOTFS}"
}

# ============================================================================
# mount_chroot / umount_chroot -- bind-mount virtual filesystems
# ============================================================================

mount_chroot() {
    local ROOTFS="$1"

    mount --bind /proc "${ROOTFS}/proc" 2>/dev/null || true
    mount --bind /sys  "${ROOTFS}/sys"  2>/dev/null || true
    mount --bind /dev  "${ROOTFS}/dev"  2>/dev/null || true
    mount --bind /dev/pts "${ROOTFS}/dev/pts" 2>/dev/null || true
}

umount_chroot() {
    local ROOTFS="$1"

    umount "${ROOTFS}/dev/pts" 2>/dev/null || true
    umount "${ROOTFS}/dev"     2>/dev/null || true
    umount "${ROOTFS}/sys"     2>/dev/null || true
    umount "${ROOTFS}/proc"    2>/dev/null || true
}

# ============================================================================
# install_stratura_pkgs -- install Stratura services into rootfs
# ============================================================================

install_stratura_pkgs() {
    local ROOTFS="$1"

    "${SCRIPTS_DIR}/common/install-stratura-pkgs.sh" "${ROOTFS}" "${PACKAGES_DIR}"
}

# ============================================================================
# customize_rootfs -- apply common + target-specific customization
# ============================================================================

customize_rootfs() {
    local ROOTFS="$1"
    local TARGET="$2"

    # Common customization
    "${SCRIPTS_DIR}/common/customize-rootfs.sh" "${ROOTFS}"

    # Target-specific customization
    local TARGET_SCRIPT="${SCRIPTS_DIR}/${TARGET}/customize-rootfs.sh"
    if [ -x "${TARGET_SCRIPT}" ]; then
        "${TARGET_SCRIPT}" "${ROOTFS}"
    fi
}

# ============================================================================
# apply_overlays -- rsync overlay files into rootfs
# ============================================================================

apply_overlays() {
    local ROOTFS="$1"
    local TARGET="$2"

    # Common overlay
    if [ -d "${OVERLAY_DIR}/common" ]; then
        rsync -a "${OVERLAY_DIR}/common/" "${ROOTFS}/"
    fi

    # Target-specific overlay
    if [ -d "${OVERLAY_DIR}/${TARGET}" ]; then
        rsync -a "${OVERLAY_DIR}/${TARGET}/" "${ROOTFS}/"
    fi
}

# ============================================================================
# set_root_password -- set root password inside chroot
# ============================================================================

set_root_password() {
    local ROOTFS="$1"

    mount_chroot "${ROOTFS}"
    chroot "${ROOTFS}" sh -c "echo 'root:${STRATURAOS_ROOT_PASSWD}' | chpasswd"
    umount_chroot "${ROOTFS}"
}

# ============================================================================
# create_docker_image -- create Docker rootfs tarball
# ============================================================================

create_docker_image() {
    print_status "Building Docker target..."

    local OUTPUT_DIR="${RELEASE_DIR}/${VERSION}/docker"
    local ARCH="amd64"

    # Detect if we should build arm64 based on host
    local HOST_ARCH
    HOST_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    if [ "${HOST_ARCH}" = "arm64" ]; then
        ARCH="arm64"
    fi

    "${SCRIPTS_DIR}/docker/create-image.sh" "${OUTPUT_DIR}" "${ARCH}"
}

# ============================================================================
# create_rpi5_image -- assemble RPi5 SD card image via sfdisk + losetup
# ============================================================================

create_rpi5_image() {
    local ROOTFS="$1"
    local OUTPUT_DIR="${RELEASE_DIR}/${VERSION}/arm64"

    "${SCRIPTS_DIR}/rpi5/create-image.sh" "${ROOTFS}" "${OUTPUT_DIR}"
}

# ============================================================================
# create_x86_iso -- placeholder for Phase 2
# ============================================================================

create_x86_iso() {
    local ROOTFS="$1"
    local OUTPUT_DIR="${RELEASE_DIR}/${VERSION}/iso"

    if [ -x "${SCRIPTS_DIR}/x86_64/create-iso.sh" ]; then
        "${SCRIPTS_DIR}/x86_64/create-iso.sh" "${ROOTFS}" "${OUTPUT_DIR}"
    else
        print_warning "scripts/x86_64/create-iso.sh not found (Phase 2)."
        print_warning "Skipping ISO creation."
    fi
}

# ============================================================================
# package_release -- generate checksums and GPG signatures
# ============================================================================

package_release() {
    local TARGET="$1"
    local TARGET_DIR

    case "${TARGET}" in
        rpi5)   TARGET_DIR="${RELEASE_DIR}/${VERSION}/arm64" ;;
        iso)    TARGET_DIR="${RELEASE_DIR}/${VERSION}/iso" ;;
        docker) TARGET_DIR="${RELEASE_DIR}/${VERSION}/docker" ;;
        *)      return 0 ;;
    esac

    if [ ! -d "${TARGET_DIR}" ]; then
        return 0
    fi

    # Check if there are any release files
    if ! ls "${TARGET_DIR}"/straturaos-* 1>/dev/null 2>&1; then
        return 0
    fi

    print_status "Generating checksums for ${TARGET}..."

    (
        cd "${TARGET_DIR}"
        sha512sum straturaos-"${VERSION}"-* > SHA512SUMS 2>/dev/null || true

        # GPG sign if key is available
        if command -v gpg >/dev/null 2>&1 && gpg --list-secret-keys 2>/dev/null | grep -q "sec"; then
            for file in straturaos-"${VERSION}"-*; do
                if [ -f "${file}" ] && [[ ! "${file}" =~ \.sign$ ]]; then
                    gpg --yes --detach-sign -o "${file}.sign" "${file}" 2>/dev/null || true
                fi
            done
            gpg --yes --detach-sign -o "SHA512SUMS.sign" SHA512SUMS 2>/dev/null || true
        fi
    )
}

# ============================================================================
# cleanup_old_artifacts -- remove old release files, keeping N most recent
# ============================================================================

cleanup_old_artifacts() {
    local KEEP_COUNT=${1:-1}
    print_status "Cleaning up old artifacts (keeping last ${KEEP_COUNT})..."

    echo ""
    df -h / 2>/dev/null | head -2
    echo ""

    if [ -d "${RELEASE_DIR}" ]; then
        for version_dir in "${RELEASE_DIR}"/*/; do
            if [ ! -d "${version_dir}" ]; then continue; fi
            for arch_dir in "${version_dir}"/*/; do
                if [ ! -d "${arch_dir}" ]; then continue; fi

                for ext in img iso tar qcow2; do
                    local COUNT=0
                    # shellcheck disable=SC2206
                    local FILES=( "${arch_dir}"straturaos-*.${ext} )
                    [[ -e "${FILES[0]}" ]] && COUNT=${#FILES[@]}
                    if [ "${COUNT}" -gt "${KEEP_COUNT}" ]; then
                        print_status "Removing old .${ext} files in $(basename "${arch_dir}")..."
                        # shellcheck disable=SC2012
                        ls -1t "${arch_dir}"straturaos-*.${ext} 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read -r f; do
                            echo "  Removing: $(basename "${f}")"
                            rm -f "${f}" "${f}.sign"
                        done
                    fi
                done
            done
        done
    fi

    # Clean Docker images
    if command -v docker >/dev/null 2>&1; then
        local DOCKER_IMAGES
        DOCKER_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep '^straturaos:' | grep -v ':latest' | sort -r || true)
        local DOCKER_COUNT=0
        if [ -n "${DOCKER_IMAGES}" ]; then
            DOCKER_COUNT=$(echo "${DOCKER_IMAGES}" | wc -l | tr -d ' ')
        fi

        if [ "${DOCKER_COUNT:-0}" -gt "${KEEP_COUNT}" ]; then
            print_status "Removing old Docker images..."
            echo "${DOCKER_IMAGES}" | tail -n +$((KEEP_COUNT + 1)) | while read -r img; do
                if [ -n "${img}" ]; then
                    echo "  Removing: ${img}"
                    docker rmi "${img}" 2>/dev/null || true
                fi
            done
        fi
    fi

    # Clean temporary build files
    rm -rf "${STRATURAOS_TMP}"/straturaos-* 2>/dev/null || true

    echo ""
    print_status "Disk usage after cleanup:"
    df -h / 2>/dev/null | head -2

    print_status "Cleanup complete!"
}

# ============================================================================
# clean_build -- remove rootfs and temp dirs
# ============================================================================

clean_build() {
    print_status "Cleaning build directories..."

    rm -rf "${STRATURAOS_TMP}"/straturaos-rootfs-* 2>/dev/null || true
    rm -rf "${STRATURAOS_TMP}"/straturaos-docker-* 2>/dev/null || true
    rm -rf "${STRATURAOS_TMP}"/straturaos-iso-* 2>/dev/null || true

    print_status "Clean complete!"
}

# ============================================================================
# build_supervisor -- build Docker supervisor image and save to rootfs
# ============================================================================

build_supervisor() {
    local ROOTFS="$1"

    print_status "Building supervisor container image..."

    if [ ! -d "${PROJECT_DIR}/supervisor" ]; then
        print_error "supervisor/ directory not found. Cannot build supervisor image."
        exit 1
    fi

    # Build the Docker image
    docker build -t "stratura/supervisor:${STRATURAOS_VERSION}" "${PROJECT_DIR}/supervisor/"

    # Save as tar for embedding in rootfs
    install -d "${ROOTFS}/var/lib/stratura"
    docker save "stratura/supervisor:${STRATURAOS_VERSION}" \
        -o "${ROOTFS}/var/lib/stratura/supervisor.tar"

    print_status "Supervisor image saved to rootfs"
}

# ============================================================================
# build_target -- main pipeline dispatcher
# ============================================================================

build_target() {
    local TARGET="$1"
    local BUILD_START
    BUILD_START=$(date +%s)

    local TARGET_LABEL
    case "${TARGET}" in
        rpi5)   TARGET_LABEL="RPi5 SD Card Image (arm64)" ;;
        iso)    TARGET_LABEL="x86_64 Hybrid ISO (amd64)" ;;
        docker) TARGET_LABEL="Docker Rootfs Tarball" ;;
    esac

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Building: ${TARGET_LABEL}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Version:  ${VERSION}"
    echo -e "  Suite:    ${STRATURAOS_DEBIAN_SUITE}"
    echo -e "  Mirror:   ${STRATURAOS_DEBIAN_MIRROR}"
    echo -e "  Tmp dir:  ${STRATURAOS_TMP}"
    echo -e "  Release:  ${RELEASE_DIR}/${VERSION}/"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Docker is a separate pipeline (its own mmdebstrap)
    if [ "${TARGET}" = "docker" ]; then
        create_docker_image
        package_release "docker"
        print_build_summary "docker" "${BUILD_START}"
        return
    fi

    local ARCH="amd64"
    [ "${TARGET}" = "rpi5" ] && ARCH="arm64"

    # Map target name to directory name used for scripts/config/overlay paths
    # "iso" target uses "x86_64" directories, "rpi5" uses "rpi5"
    local TARGET_DIRNAME="${TARGET}"
    [ "${TARGET}" = "iso" ] && TARGET_DIRNAME="x86_64"

    local ROOTFS="${STRATURAOS_TMP}/straturaos-rootfs-${TARGET}"
    rm -rf "${ROOTFS}"

    # Phase 1: Bootstrap
    print_status "[1/7] Bootstrapping Debian ${STRATURAOS_DEBIAN_SUITE} (${ARCH})..."
    print_status "  Rootfs: ${ROOTFS}"
    bootstrap_rootfs "${ROOTFS}" "${ARCH}"

    # Phase 2: Install Debian packages
    print_status "[2/7] Installing Debian packages (common + ${TARGET_DIRNAME})..."
    print_status "  Package lists: ${CONFIG_DIR}/packages-common.list, ${CONFIG_DIR}/packages-${TARGET_DIRNAME}.list"
    install_packages "${ROOTFS}" "${TARGET_DIRNAME}"

    # Phase 3: Install Stratura packages
    print_status "[3/7] Installing Stratura packages..."
    print_status "  Source: ${PACKAGES_DIR}/"
    install_stratura_pkgs "${ROOTFS}"

    # Phase 4: Build supervisor container
    print_status "[4/7] Building supervisor container..."
    build_supervisor "${ROOTFS}"

    # Phase 5: Customize
    print_status "[5/7] Customizing rootfs (common + ${TARGET_DIRNAME})..."
    apply_overlays "${ROOTFS}" "${TARGET_DIRNAME}"
    customize_rootfs "${ROOTFS}" "${TARGET_DIRNAME}"
    set_root_password "${ROOTFS}"

    # Phase 6: Create artifact
    print_status "[6/7] Creating ${TARGET_LABEL}..."
    case "${TARGET}" in
        rpi5) create_rpi5_image "${ROOTFS}" ;;
        iso)  create_x86_iso "${ROOTFS}" ;;
    esac

    # Phase 7: Package release
    print_status "[7/7] Packaging release..."
    package_release "${TARGET}"
    print_build_summary "${TARGET}" "${BUILD_START}"

    # Cleanup rootfs
    rm -rf "${ROOTFS}"
}

# ============================================================================
# show_help
# ============================================================================

show_help() {
    echo "StraturaOS Build System (Debian)"
    echo ""
    echo "Usage: ./build.sh [command]"
    echo ""
    echo "Commands:"
    echo "  setup              Install host build dependencies"
    echo "  build {target}     Build StraturaOS image"
    echo "  clean              Remove build rootfs and temp files"
    echo "  help               Show this help message"
    echo ""
    echo "Build targets:"
    echo "  docker             Docker rootfs tarball (fastest validation)"
    echo "  iso                x86_64 hybrid BIOS+EFI ISO"
    echo "  rpi5               ARM64 RPi5 SD card image"
    echo "  all                Build all targets"
    echo ""
    echo "Quick start:"
    echo "  ./build.sh setup          # First time only (installs host deps)"
    echo "  ./build.sh build docker   # Build Docker image (fastest)"
    echo "  ./build.sh build iso      # Build x86_64 ISO"
    echo "  ./build.sh build rpi5     # Build RPi5 SD card image"
    echo "  ./build.sh build all      # Build all targets"
    echo ""
    echo "Docker images created:"
    echo "  straturaos:latest-arm64     # RPi5 build"
    echo "  straturaos:latest-amd64     # x86_64 build"
}

# ============================================================================
# Main
# ============================================================================

case "${1:-help}" in
    setup)
        setup_host
        ;;
    build)
        TARGET="${2:-all}"
        cleanup_old_artifacts 1

        case "${TARGET}" in
            all)
                print_status "Building all targets..."
                local START_TIME
                START_TIME=$(date +%s)
                build_target "docker"
                build_target "iso"
                build_target "rpi5"
                local ELAPSED=$(( $(date +%s) - START_TIME ))
                local MINS=$(( ELAPSED / 60 ))
                local SECS=$(( ELAPSED % 60 ))
                echo ""
                echo -e "${GREEN}[StraturaOS]${NC} ${BOLD}All targets built successfully!${NC} (${MINS}m ${SECS}s)"
                echo ""
                ;;
            docker|iso|rpi5)
                build_target "${TARGET}"
                ;;
            *)
                print_error "Unknown target: ${TARGET}. Use 'docker', 'iso', 'rpi5', or 'all'."
                exit 1
                ;;
        esac
        ;;
    clean)
        clean_build
        ;;
    cleanup)
        cleanup_old_artifacts 1
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
