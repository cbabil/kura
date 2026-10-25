#!/bin/bash
# OS Build Script (Debian)
# Usage: ./build.sh [command]
#
# Commands:
#   setup            - Install host dependencies for Debian builds
#   build {target}   - Build OS image (rpi5|pc|docker|all)
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

EXPECTED_CONF_VERSION="4"

OS_CONF_VERSION="${OS_CONF_VERSION:-${EXPECTED_CONF_VERSION}}"

if [ "${OS_CONF_VERSION}" != "${EXPECTED_CONF_VERSION}" ]; then
    echo -e "\033[1;33m[WARNING]\033[0m .env version mismatch (have: ${OS_CONF_VERSION}, expected: ${EXPECTED_CONF_VERSION})"
    echo -e "\033[1;33m[WARNING]\033[0m Your .env may need updating. See .env.example for current variables."
fi

# ============================================================================
# Defaults
# ============================================================================

# Single source of truth for default brand values
# shellcheck disable=SC1091
source "${PROJECT_DIR}/scripts/common/brand-defaults.sh"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/scripts/common/docker-repo.sh"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/scripts/common/install-firstboot.sh"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/scripts/common/passwords.sh"
# shellcheck disable=SC1091
source "${PROJECT_DIR}/scripts/common/verify-rootfs.sh"

OS_DEBIAN_SUITE="${OS_DEBIAN_SUITE:-trixie}"
OS_DEBIAN_MIRROR="${OS_DEBIAN_MIRROR:-https://deb.debian.org/debian}"
OS_CROSS_BUILD="${OS_CROSS_BUILD:-auto}"
OS_PARALLEL_JOBS="${OS_PARALLEL_JOBS:-$(nproc 2>/dev/null || echo 1)}"
OS_BRAND="${OS_BRAND:-${DEFAULT_BRAND}}"
OS_NAME="${OS_NAME:-${DEFAULT_NAME}}"
OS_VERSION="${OS_VERSION:-2.0}"
OS_HOSTNAME="${OS_HOSTNAME:-${DEFAULT_HOSTNAME}}"
OS_ROOT_PASSWD="${OS_ROOT_PASSWD:-}"   # empty: root's password is locked
OS_ISSUE="${OS_ISSUE:-Welcome to ${DEFAULT_NAME}}"
OS_DHCP_INTERFACE="${OS_DHCP_INTERFACE:-eth0}"
OS_ROOTFS_SIZE="${OS_ROOTFS_SIZE:-2G}"
OS_PC_ROOTFS_SIZE="${OS_PC_ROOTFS_SIZE:-3G}"
OS_TMP="${OS_TMP:-${DEFAULT_TMP}}"
OS_COLOR="${OS_COLOR:-${DEFAULT_COLOR}}"
OS_JOURNAL_MAX_SIZE="${OS_JOURNAL_MAX_SIZE:-100M}"
OS_JOURNAL_MAX_FILE_SEC="${OS_JOURNAL_MAX_FILE_SEC:-1week}"

export OS_CONF_VERSION OS_DEBIAN_SUITE OS_DEBIAN_MIRROR
export OS_CROSS_BUILD OS_PARALLEL_JOBS OS_BRAND OS_NAME
export OS_VERSION OS_HOSTNAME OS_ROOT_PASSWD OS_ISSUE
export OS_DHCP_INTERFACE OS_ROOTFS_SIZE OS_PC_ROOTFS_SIZE OS_TMP
export OS_COLOR OS_JOURNAL_MAX_SIZE OS_JOURNAL_MAX_FILE_SEC

mkdir -p "${OS_TMP}" 2>/dev/null || true

# Derived brand variables
BRAND="${OS_BRAND}"
ARTIFACT_PREFIX="${BRAND}"

# Shared paths
RELEASE_DIR="${PROJECT_DIR}/release"
PACKAGES_DIR="${PROJECT_DIR}/packages"
SCRIPTS_DIR="${PROJECT_DIR}/scripts"
OVERLAY_DIR="${PROJECT_DIR}/overlay"
CONFIG_DIR="${PROJECT_DIR}/config"
VERSION="${OS_VERSION}"
BUILD_DATE=$(date +%Y%m%d)
# Build number (auto-incremented, zero-padded, stored in .build-number)
BUILD_NUMBER_FILE="${PROJECT_DIR}/.build-number"
if [ -f "${BUILD_NUMBER_FILE}" ]; then
    OS_BUILD_NUMBER=$(cat "${BUILD_NUMBER_FILE}")
else
    OS_BUILD_NUMBER=0
fi
OS_BUILD_NUMBER=$((OS_BUILD_NUMBER + 1))
echo "${OS_BUILD_NUMBER}" > "${BUILD_NUMBER_FILE}"
OS_BUILD_SEQ=$(printf "%04d" "${OS_BUILD_NUMBER}")
export BUILD_DATE OS_BUILD_SEQ

# ============================================================================
# Color output helpers
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[${OS_NAME}]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

CYAN='\033[0;36m'
BOLD='\033[1m'

# print_build_all_summary -- combined summary for build all
print_build_all_summary() {
    local MINS="$1"
    local SECS="$2"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}${OS_NAME} — All Targets Built${NC} (${MINS}m ${SECS}s)"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    print_build_section "docker"
    print_build_section "pc"
    print_build_section "rpi5"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# print_build_section -- print artifact details for a single target (no box)
print_build_section() {
    local TARGET="$1"
    local TARGET_DIR=""

    case "${TARGET}" in
        rpi5)   TARGET_DIR="${RELEASE_DIR}/${VERSION}/arm64" ;;
        pc)     TARGET_DIR="${RELEASE_DIR}/${VERSION}/pc" ;;
        docker) TARGET_DIR="${RELEASE_DIR}/${VERSION}/docker" ;;
    esac

    [ -z "${TARGET_DIR}" ] && return 0
    [ ! -d "${TARGET_DIR}" ] && return 0

    local TARGET_LABEL=""
    case "${TARGET}" in
        rpi5)   TARGET_LABEL="RPi5 SD Card Image" ;;
        pc)     TARGET_LABEL="x86_64 PC Disk Image" ;;
        docker) TARGET_LABEL="Docker Rootfs Tarball" ;;
    esac

    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}${TARGET_LABEL}${NC}"
    echo -e "${GREEN}║${NC}    Path: ${TARGET_DIR}/"

    local file
    for file in "${TARGET_DIR}"/${ARTIFACT_PREFIX}-"${VERSION}"-*; do
        [ -f "${file}" ] || continue
        [[ "${file}" =~ \.sign$ ]] && continue
        [[ "$(basename "${file}")" = "SHA512SUMS" ]] && continue
        local SIZE
        SIZE=$(du -h "${file}" 2>/dev/null | cut -f1) || SIZE="?"
        echo -e "${GREEN}║${NC}    ${CYAN}$(basename "${file}")${NC}  (${SIZE})"
    done

    if [ -f "${TARGET_DIR}/SHA512SUMS" ]; then
        echo -e "${GREEN}║${NC}"
        echo -e "${GREEN}║${NC}    ${BOLD}SHA512SUMS:${NC}"
        while IFS= read -r line; do
            echo -e "${GREEN}║${NC}      ${line}"
        done < "${TARGET_DIR}/SHA512SUMS"
    fi
    return 0
}

# print_build_summary -- show a boxed summary for a single target build
print_build_summary() {
    local TARGET="$1"
    local BUILD_START="${2:-}"

    local DURATION=""
    if [ -n "${BUILD_START}" ]; then
        local ELAPSED=$(( $(date +%s) - BUILD_START ))
        local MINS=$(( ELAPSED / 60 ))
        local SECS=$(( ELAPSED % 60 ))
        DURATION=" (${MINS}m ${SECS}s)"
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}Build Complete${NC}${DURATION}"
    print_build_section "${TARGET}"
    echo -e "${GREEN}║${NC}"
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
        debian-archive-keyring
        arch-test
        qemu-user-static
        binfmt-support
        debootstrap
        rsync
        dosfstools
        e2fsprogs
        gdisk
        shellcheck
        bats
        curl
        gnupg
        docker.io
        containerd
        zstd
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

    # Ensure loop device support (needed for RPi5 SD card image creation)
    modprobe loop 2>/dev/null || true
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
        # CA certificates from the start: install_packages adds Docker's HTTPS
        # repo and runs apt-get update before the package list is installed.
        --include=ca-certificates
        --quiet
    )

    # Verify the Debian archive with Debian's keyring explicitly. Without it,
    # mmdebstrap trusts only the host's apt keys, which on a non-Debian host
    # (e.g. Ubuntu, as on GitHub runners) don't include Debian's, so apt fails.
    local DEBIAN_KEYRING="/usr/share/keyrings/debian-archive-keyring.gpg"
    if [ -f "${DEBIAN_KEYRING}" ]; then
        MMDEBSTRAP_OPTS+=("--keyring=${DEBIAN_KEYRING}")
    fi

    # Cross-build detection
    local HOST_ARCH
    HOST_ARCH=$(dpkg --print-architecture 2>/dev/null || echo "amd64")
    if [ "${ARCH}" != "${HOST_ARCH}" ]; then
        if [ "${OS_CROSS_BUILD}" = "no" ]; then
            print_error "Cross-build required (host=${HOST_ARCH}, target=${ARCH}) but OS_CROSS_BUILD=no"
            exit 1
        fi
        print_status "Cross-building: host=${HOST_ARCH}, target=${ARCH}"
    fi

    mmdebstrap "${MMDEBSTRAP_OPTS[@]}" \
        "${OS_DEBIAN_SUITE}" "${ROOTFS}" "${OS_DEBIAN_MIRROR}"

    print_status "Bootstrap complete."
}

# ============================================================================
# install_packages -- install Debian packages from package lists into rootfs
# ============================================================================

install_packages() {
    local ROOTFS="$1"
    local TARGET="$2"      # script directory name: rpi5 | x86_64
    local DEB_ARCH="$3"    # Debian architecture: arm64 | amd64

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

    # Suppress debconf dialog warnings inside chroot
    export DEBIAN_FRONTEND=noninteractive

    # Prevent daemons from starting during package installation (standard
    # Debian image-build practice).  Without this, packages like docker.io
    # fail their postinst when they try to start services in a chroot.
    cat > "${ROOTFS}/usr/sbin/policy-rc.d" <<'POLICYEOF'
#!/bin/sh
exit 101
POLICYEOF
    chmod +x "${ROOTFS}/usr/sbin/policy-rc.d"

    # Run per-target repo configuration (e.g. RPi APT repo, non-free-firmware)
    local REPO_SCRIPT="${SCRIPTS_DIR}/${TARGET}/configure-repos.sh"
    if [ -x "${REPO_SCRIPT}" ]; then
        "${REPO_SCRIPT}" "${ROOTFS}"
    fi

    # Docker's APT repo (key fingerprint verified on the host) for every target
    install_docker_repo "${ROOTFS}" "${DEB_ARCH}"

    if [ -n "${PACKAGES}" ]; then
        # shellcheck disable=SC2086
        chroot "${ROOTFS}" apt-get update -qq 2>&1 | grep -v "^$" || true
        # shellcheck disable=SC2086
        chroot "${ROOTFS}" apt-get install -y -qq --no-install-recommends ${PACKAGES}
    fi

    # Purge build-only packages no longer needed at runtime
    print_status "Purging build-only packages..."
    chroot "${ROOTFS}" apt-get purge -y -qq gnupg 2>/dev/null || true
    chroot "${ROOTFS}" apt-get autoremove -y -qq 2>/dev/null || true
    chroot "${ROOTFS}" apt-get clean -qq
    rm -rf "${ROOTFS}/var/cache/apt/archives"/*.deb
    rm -rf "${ROOTFS}/var/lib/apt/lists"/*

    # Remove the policy that blocks daemons — services should start at boot
    rm -f "${ROOTFS}/usr/sbin/policy-rc.d"

    umount_chroot "${ROOTFS}"
}

# ============================================================================
# mount_chroot / umount_chroot -- bind-mount virtual filesystems
# ============================================================================

mount_chroot() {
    local ROOTFS="$1"

    install -d "${ROOTFS}/proc" "${ROOTFS}/sys" "${ROOTFS}/dev" "${ROOTFS}/dev/pts"
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
# install_os_pkgs -- install OS services into rootfs
# ============================================================================

install_os_pkgs() {
    local ROOTFS="$1"

    "${SCRIPTS_DIR}/common/install-os-pkgs.sh" "${ROOTFS}" "${PACKAGES_DIR}"
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

    # Remove previous tarballs so only the new one remains
    rm -f "${OUTPUT_DIR}"/${ARTIFACT_PREFIX}-*.tar* "${OUTPUT_DIR}"/SHA512SUMS* 2>/dev/null || true

    "${SCRIPTS_DIR}/docker/create-image.sh" "${OUTPUT_DIR}" "${ARCH}"
}

# ============================================================================
# create_rpi5_image -- assemble RPi5 SD card image via sfdisk + losetup
# ============================================================================

create_rpi5_image() {
    local ROOTFS="$1"
    local OUTPUT_DIR="${RELEASE_DIR}/${VERSION}/arm64"

    # Remove previous images so only the new one remains
    rm -f "${OUTPUT_DIR}"/${ARTIFACT_PREFIX}-*.img* "${OUTPUT_DIR}"/SHA512SUMS* 2>/dev/null || true

    "${SCRIPTS_DIR}/rpi5/create-image.sh" "${ROOTFS}" "${OUTPUT_DIR}"
}

# ============================================================================
# create_pc_image -- assemble the x86 PC disk image (UEFI, GPT)
# ============================================================================

create_pc_image() {
    local ROOTFS="$1"
    local OUTPUT_DIR="${RELEASE_DIR}/${VERSION}/pc"

    # Remove previous images so only the new one remains
    rm -f "${OUTPUT_DIR}"/${ARTIFACT_PREFIX}-*.img* "${OUTPUT_DIR}"/SHA512SUMS* 2>/dev/null || true

    "${SCRIPTS_DIR}/x86_64/create-image.sh" "${ROOTFS}" "${OUTPUT_DIR}"
}

# ============================================================================
# package_release -- generate checksums and GPG signatures
# ============================================================================

package_release() {
    local TARGET="$1"
    local TARGET_DIR

    case "${TARGET}" in
        rpi5)   TARGET_DIR="${RELEASE_DIR}/${VERSION}/arm64" ;;
        pc)     TARGET_DIR="${RELEASE_DIR}/${VERSION}/pc" ;;
        docker) TARGET_DIR="${RELEASE_DIR}/${VERSION}/docker" ;;
        *)      return 0 ;;
    esac

    if [ ! -d "${TARGET_DIR}" ]; then
        return 0
    fi

    # Check if there are any release files
    if ! ls "${TARGET_DIR}"/${ARTIFACT_PREFIX}-* 1>/dev/null 2>&1; then
        return 0
    fi

    print_status "Generating checksums for ${TARGET}..."

    # Local builds are unsigned dev builds. Releases are signed keylessly by
    # .github/workflows/release.yml on v* tags (Sigstore, ADR-012).
    (
        cd "${TARGET_DIR}"
        sha512sum ${ARTIFACT_PREFIX}-"${VERSION}"-* > SHA512SUMS 2>/dev/null || true
    ) || true
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

                for ext in img tar qcow2; do
                    local COUNT=0
                    # shellcheck disable=SC2206
                    local FILES=( "${arch_dir}"${ARTIFACT_PREFIX}-*.${ext} )
                    [[ -e "${FILES[0]}" ]] && COUNT=${#FILES[@]}
                    if [ "${COUNT}" -gt "${KEEP_COUNT}" ]; then
                        print_status "Removing old .${ext} files in $(basename "${arch_dir}")..."
                        # shellcheck disable=SC2012
                        ls -1t "${arch_dir}"${ARTIFACT_PREFIX}-*.${ext} 2>/dev/null | tail -n +$((KEEP_COUNT + 1)) | while read -r f; do
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
        DOCKER_IMAGES=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep "^${ARTIFACT_PREFIX}:" | grep -v ':latest' | sort -r || true)
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
    rm -rf "${OS_TMP}"/${ARTIFACT_PREFIX}-* 2>/dev/null || true

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

    rm -rf "${OS_TMP}"/${ARTIFACT_PREFIX}-rootfs-* 2>/dev/null || true
    rm -rf "${OS_TMP}"/${ARTIFACT_PREFIX}-docker-* 2>/dev/null || true

    print_status "Clean complete!"
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
        pc)     TARGET_LABEL="x86_64 PC Disk Image (amd64, UEFI)" ;;
        docker) TARGET_LABEL="Docker Rootfs Tarball" ;;
    esac

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}  Building: ${TARGET_LABEL}${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Version:  ${VERSION}"
    echo -e "  Suite:    ${OS_DEBIAN_SUITE}"
    echo -e "  Mirror:   ${OS_DEBIAN_MIRROR}"
    echo -e "  Tmp dir:  ${OS_TMP}"
    echo -e "  Release:  ${RELEASE_DIR}/${VERSION}/"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    # Docker is a separate pipeline (its own mmdebstrap)
    if [ "${TARGET}" = "docker" ]; then
        create_docker_image
        package_release "docker"
        if [ "${_BUILD_ALL:-0}" -eq 0 ]; then
            print_build_summary "docker" "${BUILD_START}"
        fi
        return 0
    fi

    # Debian architecture, and the directory name used for the target's
    # scripts, package list and overlay
    local ARCH TARGET_DIRNAME
    case "${TARGET}" in
        rpi5) ARCH="arm64"; TARGET_DIRNAME="rpi5" ;;
        pc)   ARCH="amd64"; TARGET_DIRNAME="x86_64" ;;
    esac

    local ROOTFS="${OS_TMP}/${ARTIFACT_PREFIX}-rootfs-${TARGET}"

    # Ensure chroot mounts are cleaned up on failure (use global for trap visibility)
    _CLEANUP_ROOTFS="${ROOTFS}"
    trap 'umount_chroot "${_CLEANUP_ROOTFS}" 2>/dev/null' EXIT

    # Clean up stale mounts from any previous interrupted build
    umount_chroot "${ROOTFS}" 2>/dev/null
    rm -rf "${ROOTFS}"

    # Phase 1: Bootstrap
    print_status "[1/6] Bootstrapping Debian ${OS_DEBIAN_SUITE} (${ARCH})..."
    print_status "  Rootfs: ${ROOTFS}"
    bootstrap_rootfs "${ROOTFS}" "${ARCH}"

    # Phase 2: Install Debian packages
    print_status "[2/6] Installing Debian packages (common + ${TARGET_DIRNAME})..."
    print_status "  Package lists: ${CONFIG_DIR}/packages-common.list, ${CONFIG_DIR}/packages-${TARGET_DIRNAME}.list"
    install_packages "${ROOTFS}" "${TARGET_DIRNAME}" "${ARCH}"

    # Phase 3: Install OS packages
    print_status "[3/6] Installing OS packages..."
    print_status "  Source: ${PACKAGES_DIR}/"
    install_os_pkgs "${ROOTFS}"

    # Phase 4: Customize
    print_status "[4/6] Customizing rootfs (common + ${TARGET_DIRNAME})..."
    apply_overlays "${ROOTFS}" "${TARGET_DIRNAME}"
    customize_rootfs "${ROOTFS}" "${TARGET_DIRNAME}"
    set_passwords "${ROOTFS}"
    # Each flashed device must get its own SSH host keys and machine ID
    reset_device_identity "${ROOTFS}"

    # Verify critical files, enable links and device identity (fail fast)
    print_status "Verifying rootfs..."
    if ! verify_rootfs "${ROOTFS}" "${BRAND}"; then
        print_error "Rootfs verification failed — aborting"
        exit 1
    fi
    print_status "Rootfs verification passed"

    # Phase 5: Create artifact
    print_status "[5/6] Creating ${TARGET_LABEL}..."
    case "${TARGET}" in
        rpi5) create_rpi5_image "${ROOTFS}" ;;
        pc)   create_pc_image "${ROOTFS}" ;;
    esac

    # Phase 6: Package release
    print_status "[6/6] Packaging release..."
    package_release "${TARGET}"
    if [ "${_BUILD_ALL:-0}" -eq 0 ]; then
        print_build_summary "${TARGET}" "${BUILD_START}"
    fi

    # Cleanup rootfs
    rm -rf "${ROOTFS}"
    trap - EXIT
}

# ============================================================================
# show_help
# ============================================================================

show_help() {
    echo "${OS_NAME} Build System (Debian)"
    echo ""
    echo "Usage: ./build.sh [command]"
    echo ""
    echo "Commands:"
    echo "  setup              Install host build dependencies"
    echo "  build {target}     Build ${OS_NAME} image"
    echo "  clean              Remove build rootfs and temp files"
    echo "  help               Show this help message"
    echo ""
    echo "Build targets:"
    echo "  docker             Docker rootfs tarball (fastest validation)"
    echo "  pc                 x86_64 PC disk image (UEFI, e.g. Intel NUC)"
    echo "  rpi5               ARM64 RPi5 SD card image"
    echo "  all                Build all targets"
    echo ""
    echo "Quick start:"
    echo "  ./build.sh setup          # First time only (installs host deps)"
    echo "  ./build.sh build docker   # Build Docker image (fastest)"
    echo "  ./build.sh build pc       # Build x86_64 PC disk image"
    echo "  ./build.sh build rpi5     # Build RPi5 SD card image"
    echo "  ./build.sh build all      # Build all targets"
    echo ""
    echo "Docker images created:"
    echo "  ${ARTIFACT_PREFIX}:latest-arm64     # RPi5 build"
    echo "  ${ARTIFACT_PREFIX}:latest-amd64     # x86_64 build"
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
                START_TIME=$(date +%s)
                _BUILD_ALL=1
                build_target "docker"
                echo ""
                echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
                echo -e "${GREEN}  ✓ Docker complete — continuing with PC...${NC}"
                echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
                build_target "pc"
                echo ""
                echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
                echo -e "${GREEN}  ✓ PC complete — continuing with RPi5...${NC}"
                echo -e "${GREEN}────────────────────────────────────────────────────────────────${NC}"
                build_target "rpi5"
                _BUILD_ALL=0
                ELAPSED=$(( $(date +%s) - START_TIME ))
                MINS=$(( ELAPSED / 60 ))
                SECS=$(( ELAPSED % 60 ))
                print_build_all_summary "${MINS}" "${SECS}"
                ;;
            docker|pc|rpi5)
                build_target "${TARGET}"
                ;;
            *)
                print_error "Unknown target: ${TARGET}. Use 'docker', 'pc', 'rpi5', or 'all'."
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
