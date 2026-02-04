#!/bin/bash
# Diagnostic script to find legacy config issues in Buildroot
# Run this on the VM: ./diagnose-legacy.sh

set -e

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILDROOT_DIR="${SCRIPT_DIR}/../buildroot"

if [ -d "${SCRIPT_DIR}/buildroot-external" ]; then
    EXTERNAL_DIR="${SCRIPT_DIR}/buildroot-external"
else
    EXTERNAL_DIR="${SCRIPT_DIR}"
fi

echo "=== StraturaOS Legacy Config Diagnostic ==="
echo ""

# Check Buildroot version
echo "1. Checking Buildroot version..."
if [ -d "${BUILDROOT_DIR}" ]; then
    cd "${BUILDROOT_DIR}"
    CURRENT_TAG=$(git describe --tags --exact-match 2>/dev/null || echo "not on a tag")
    CURRENT_COMMIT=$(git rev-parse --short HEAD)
    echo "   Version: ${CURRENT_TAG} (${CURRENT_COMMIT})"
else
    echo "   ERROR: Buildroot not found at ${BUILDROOT_DIR}"
    exit 1
fi

# Check for existing .config
echo ""
echo "2. Checking for existing .config files..."
if [ -f "${BUILDROOT_DIR}/.config" ]; then
    echo "   FOUND: ${BUILDROOT_DIR}/.config"
    echo "   Size: $(wc -l < "${BUILDROOT_DIR}/.config") lines"

    # Check for BR2_LEGACY
    if grep -q "BR2_LEGACY=y" "${BUILDROOT_DIR}/.config"; then
        echo "   *** BR2_LEGACY=y IS SET ***"
    else
        echo "   BR2_LEGACY is not set (good)"
    fi
else
    echo "   No .config found (good - clean state)"
fi

# Clean and try loading defconfig
echo ""
echo "3. Cleaning and loading defconfig..."
cd "${BUILDROOT_DIR}"
rm -f .config .config.old 2>/dev/null || true

echo "   Loading straturaos_defconfig..."
make BR2_EXTERNAL="${EXTERNAL_DIR}" straturaos_defconfig 2>&1 | tee /tmp/defconfig-output.txt

# Check result
echo ""
echo "4. Analyzing result..."
if [ -f "${BUILDROOT_DIR}/.config" ]; then
    if grep -q "BR2_LEGACY=y" "${BUILDROOT_DIR}/.config"; then
        echo "   *** PROBLEM: BR2_LEGACY=y is set after loading defconfig ***"
        echo ""
        echo "5. Finding the trigger..."

        # Check Config.in.legacy for what triggers BR2_LEGACY
        if [ -f "${BUILDROOT_DIR}/Config.in.legacy" ]; then
            echo "   Checking Config.in.legacy..."
            TRIGGERS=$(grep -B3 "select BR2_LEGACY" "${BUILDROOT_DIR}/Config.in.legacy" | grep "^config " | sed 's/config //')

            echo ""
            echo "   Options that can trigger BR2_LEGACY:"
            for opt in ${TRIGGERS}; do
                if grep -q "^${opt}=y" "${BUILDROOT_DIR}/.config" 2>/dev/null; then
                    echo "   *** FOUND: ${opt}=y ***"
                fi
            done
        fi

        echo ""
        echo "6. Checking for known deprecated options in .config..."
        grep -E "^BR2_KERNEL_HEADERS_[0-9]|^BR2_GCC_VERSION_[0-9]|^BR2_BINUTILS_VERSION_[0-9]|^BR2_TOOLCHAIN_EXTERNAL_CODESOURCERY|^BR2_PACKAGE_PYTHON=|^BR2_PACKAGE_ORACLE_MYSQL|^BR2_PACKAGE_OPENCV=|^BR2_GDB_VERSION_[0-9]" "${BUILDROOT_DIR}/.config" 2>/dev/null || echo "   None of the common deprecated options found"
    else
        echo "   SUCCESS: Configuration loaded without BR2_LEGACY"
    fi
else
    echo "   ERROR: .config was not created"
fi

# Show defconfig output if there was an error
if grep -q "legacy configuration" /tmp/defconfig-output.txt 2>/dev/null; then
    echo ""
    echo "7. Error output from defconfig:"
    cat /tmp/defconfig-output.txt
fi

echo ""
echo "=== Diagnostic complete ==="
