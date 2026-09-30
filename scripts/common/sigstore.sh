#!/bin/bash
# scripts/common/sigstore.sh
# Keyless Sigstore verification of release assets (ADR-012). Releases are
# signed in GitHub Actions with cosign (no private key to manage); a bundle
# <asset>.sigstore.json ships next to each asset. Verification pins the
# signer to one repo's release workflow at one exact tag, so an older
# release's asset can't pass as a newer one.
# Source this file; it defines functions only.

SIGSTORE_ISSUER="https://token.actions.githubusercontent.com"

# sigstore_verify <asset> <bundle> <owner/repo> <workflow-file> <tag>
# Accepts only the certificate identity GitHub gives that workflow's run on
# that tag.
sigstore_verify() {
    local asset="$1" bundle="$2" repo="$3" workflow="$4" tag="${5:?sigstore_verify needs a tag}"
    local identity="https://github.com/${repo}/.github/workflows/${workflow}@refs/tags/${tag}"

    if ! command -v cosign >/dev/null 2>&1; then
        echo "ERROR: cosign is required to verify release signatures" >&2
        return 1
    fi
    if [ ! -f "${bundle}" ]; then
        echo "ERROR: signature bundle ${bundle} not found" >&2
        return 1
    fi

    # cosign's output goes to stderr: callers capture stdout for paths
    if ! cosign verify-blob --bundle "${bundle}" \
            --certificate-oidc-issuer "${SIGSTORE_ISSUER}" \
            --certificate-identity "${identity}" \
            "${asset}" >&2; then
        echo "ERROR: signature verification failed for ${asset}" >&2
        return 1
    fi
}
