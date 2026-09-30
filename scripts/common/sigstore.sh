#!/bin/bash
# scripts/common/sigstore.sh
# Keyless Sigstore verification of release assets (ADR-012). Releases are
# signed in GitHub Actions with cosign (no private key to manage); a bundle
# <asset>.sigstore.json ships next to each asset. Verification pins the
# signer to one repo's release workflow, at an exact tag when known.
# Source this file; it defines functions only.

SIGSTORE_ISSUER="https://token.actions.githubusercontent.com"

# sigstore_identity <owner/repo> <workflow-file> <tag>
# The certificate identity GitHub gives a workflow run on a tag.
sigstore_identity() {
    echo "https://github.com/$1/.github/workflows/$2@refs/tags/$3"
}

# sigstore_verify <asset> <bundle> <owner/repo> <workflow-file> [tag]
# With a tag, only that tag's run may have signed the asset; without one,
# any v* tag of that workflow is accepted.
sigstore_verify() {
    local asset="$1" bundle="$2" repo="$3" workflow="$4" tag="${5:-}"
    local identity=() escaped

    if ! command -v cosign >/dev/null 2>&1; then
        echo "ERROR: cosign is required to verify release signatures" >&2
        return 1
    fi
    if [ ! -f "${bundle}" ]; then
        echo "ERROR: signature bundle ${bundle} not found" >&2
        return 1
    fi

    if [ -n "${tag}" ]; then
        identity=(--certificate-identity "$(sigstore_identity "${repo}" "${workflow}" "${tag}")")
    else
        escaped=$(echo "${repo}/.github/workflows/${workflow}" | sed 's/[.]/\\./g')
        identity=(--certificate-identity-regexp "^https://github\\.com/${escaped}@refs/tags/v.*")
    fi

    # cosign's output goes to stderr: callers capture stdout for paths
    if ! cosign verify-blob --bundle "${bundle}" \
            --certificate-oidc-issuer "${SIGSTORE_ISSUER}" \
            "${identity[@]}" "${asset}" >&2; then
        echo "ERROR: signature verification failed for ${asset}" >&2
        return 1
    fi
}
