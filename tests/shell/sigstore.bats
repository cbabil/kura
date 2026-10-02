#!/usr/bin/env bats
# tests/shell/sigstore.bats — tests for scripts/common/sigstore.sh (keyless
# Sigstore verification of release assets, pinned to a repo's release workflow)

bats_require_minimum_version 1.5.0   # run --separate-stderr

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
ISSUER="https://token.actions.githubusercontent.com"

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/sigstore.sh"
    CALLS="${BATS_TEST_TMPDIR}/cosign-calls"
    ASSET="${BATS_TEST_TMPDIR}/asset.bin"; echo data > "${ASSET}"
    BUNDLE="${ASSET}.sigstore.json"; echo '{}' > "${BUNDLE}"
    export CALLS
}

stub_cosign() { cosign() { echo "$*" >> "${CALLS}"; return "${COSIGN_EXIT:-0}"; }; }

@test "sigstore_verify: pins the issuer and the exact identity at the tag" {
    stub_cosign
    run sigstore_verify "${ASSET}" "${BUNDLE}" cbabil/kura release.yml v0.1.0
    [ "$status" -eq 0 ]
    [ "$(cat "${CALLS}")" = "verify-blob --bundle ${BUNDLE} --certificate-oidc-issuer ${ISSUER} --certificate-identity https://github.com/cbabil/kura/.github/workflows/release.yml@refs/tags/v0.1.0 ${ASSET}" ]
}

@test "sigstore_verify: refuses to run without a tag (no older-release replay)" {
    stub_cosign
    run sigstore_verify "${ASSET}" "${BUNDLE}" cbabil/kura release.yml
    [ "$status" -ne 0 ]
    [ ! -e "${CALLS}" ]
}

@test "sigstore_verify: keeps cosign's stdout off stdout (callers capture paths there)" {
    cosign() { echo "Verified OK"; }
    run --separate-stderr sigstore_verify "${ASSET}" "${BUNDLE}" cbabil/kura release.yml v0.1.0
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "sigstore_verify: fails when cosign rejects the bundle" {
    stub_cosign; COSIGN_EXIT=1
    run sigstore_verify "${ASSET}" "${BUNDLE}" cbabil/kura release.yml v0.1.0
    [ "$status" -ne 0 ]
    output_has "signature verification failed"
}

@test "sigstore_verify: fails when the bundle is missing" {
    stub_cosign
    run sigstore_verify "${ASSET}" "${BATS_TEST_TMPDIR}/missing.json" cbabil/kura release.yml v0.1.0
    [ "$status" -ne 0 ]
    output_has "bundle"
    [ ! -e "${CALLS}" ]
}

@test "sigstore_verify: fails clearly when cosign is not installed" {
    PATH="${BATS_TEST_TMPDIR}/nopath" run sigstore_verify "${ASSET}" "${BUNDLE}" cbabil/kura release.yml v0.1.0
    [ "$status" -ne 0 ]
    output_has "cosign"
}
