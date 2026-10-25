#!/usr/bin/env bats
# tests/shell/make-manifest.bats — scripts/release/make-manifest.sh writes the
# release manifest (updates.md section 2) the release workflow signs and publishes.

REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
SCRIPT="${REPO_ROOT}/scripts/release/make-manifest.sh"

setup() {
    load test_helper
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/scripts/common/hash.sh"
    RAW="${BATS_TEST_TMPDIR}/raw.img"; printf 'raw pi image bytes' > "${RAW}"
    IMG="${BATS_TEST_TMPDIR}/kura-0.1.0-rpi5-arm64.img.zst"; zstd -q -c "${RAW}" > "${IMG}"
    PC_RAW="${BATS_TEST_TMPDIR}/pc.img"; printf 'raw pc' > "${PC_RAW}"
    PC="${BATS_TEST_TMPDIR}/kura-0.1.0-x86_64-amd64.img.zst"; zstd -q -c "${PC_RAW}" > "${PC}"
}

@test "make-manifest: version, channel, date and one bundle per image" {
    run "${SCRIPT}" v0.1.0 cbabil/kura "${IMG}" "${PC}"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r .version)" = "0.1.0" ]
    [ "$(echo "$output" | jq -r .channel)" = "stable" ]
    matches "$(echo "$output" | jq -r .released)" "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"
    [ "$(echo "$output" | jq -r '.bundles | keys | join(",")')" = "rpi5-arm64,x86_64" ]
}

@test "make-manifest: each bundle points at the release asset with its sha256 and size" {
    run "${SCRIPT}" v0.1.0 cbabil/kura "${IMG}" "${PC}"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.bundles["rpi5-arm64"].url')" = \
      "https://github.com/cbabil/kura/releases/download/v0.1.0/kura-0.1.0-rpi5-arm64.img.zst" ]
    [ "$(echo "$output" | jq -r '.bundles["rpi5-arm64"].sha256')" = "$(file_sha256 "${IMG}")" ]
    [ "$(echo "$output" | jq -r '.bundles["rpi5-arm64"].size')" = "$(wc -c < "${IMG}" | tr -d ' ')" ]
    [ "$(echo "$output" | jq -r '.bundles["x86_64"].url')" = \
      "https://github.com/cbabil/kura/releases/download/v0.1.0/kura-0.1.0-x86_64-amd64.img.zst" ]
    [ "$(echo "$output" | jq -r '.bundles["x86_64"].size')" = "$(wc -c < "${PC}" | tr -d ' ')" ]
}

@test "make-manifest: fails without all four arguments" {
    run "${SCRIPT}" v0.1.0 cbabil/kura "${IMG}"
    [ "$status" -ne 0 ]
    output_has "Usage"
}

@test "make-manifest: a compressed image also records the unpacked size and sha256" {
    run "${SCRIPT}" v0.1.0 cbabil/kura "${IMG}" "${PC}"
    [ "$status" -eq 0 ]
    [ "$(echo "$output" | jq -r '.bundles["rpi5-arm64"].extract_size')" = "18" ]
    [ "$(echo "$output" | jq -r '.bundles["rpi5-arm64"].extract_sha256')" = "$(file_sha256 "${RAW}")" ]
    [ "$(echo "$output" | jq -r '.bundles["x86_64"].extract_size')" = "6" ]
    [ "$(echo "$output" | jq -r '.bundles["x86_64"].extract_sha256')" = "$(file_sha256 "${PC_RAW}")" ]
}
