#!/bin/bash
# scripts/common/hash.sh
# Portable file hashing (sha256sum on Linux, shasum on macOS).
# Source this file; it defines functions only.

# file_sha256 <file>
# Prints the sha256 of a file.
file_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}
