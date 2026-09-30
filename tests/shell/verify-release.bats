#!/usr/bin/env bats
# tests/shell/verify-release.bats — scripts/release/verify-release.sh verifies
# a downloaded Kura release asset against Kura's release pipeline identity.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SCRIPT="${REPO_ROOT}/scripts/release/verify-release.sh"

setup() {
    load test_helper
    ASSET="${BATS_TEST_TMPDIR}/kura-0.1.0-rpi5-arm64.img.zst"; echo img > "${ASSET}"
    echo '{}' > "${ASSET}.sigstore.json"
    # Fake cosign on PATH that records its arguments
    BIN="${BATS_TEST_TMPDIR}/bin"; mkdir -p "${BIN}"
    printf '#!/bin/bash\necho "$*" > "%s/cosign-args"\nexit "${COSIGN_EXIT:-0}"\n' "${BATS_TEST_TMPDIR}" > "${BIN}/cosign"
    chmod +x "${BIN}/cosign"
    export PATH="${BIN}:${PATH}"
}

@test "verify-release: pins Kura's release.yml workflow at the given tag" {
    run "${SCRIPT}" "${ASSET}" v0.1.0
    [ "$status" -eq 0 ]
    output_has "OK:"
    file_has "${BATS_TEST_TMPDIR}/cosign-args" "--certificate-identity https://github.com/cbabil/kura/.github/workflows/release.yml@refs/tags/v0.1.0"
    file_has "${BATS_TEST_TMPDIR}/cosign-args" "--bundle ${ASSET}.sigstore.json"
}

@test "verify-release: accepts any v* release when no tag is given" {
    run "${SCRIPT}" "${ASSET}"
    [ "$status" -eq 0 ]
    file_has "${BATS_TEST_TMPDIR}/cosign-args" "--certificate-identity-regexp"
}

@test "verify-release: fails when the signature is invalid" {
    COSIGN_EXIT=1 run "${SCRIPT}" "${ASSET}" v0.1.0
    [ "$status" -ne 0 ]
    output_has "verification failed"
}

@test "verify-release: fails when the bundle is missing" {
    rm "${ASSET}.sigstore.json"
    run "${SCRIPT}" "${ASSET}" v0.1.0
    [ "$status" -ne 0 ]
    output_has "bundle"
}
