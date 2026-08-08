#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
CI="$ROOT/.github/workflows/ci.yml"
RELEASE="$ROOT/.github/workflows/release.yml"
[ -f "$CI" ] && [ -f "$RELEASE" ]
[ ! -f "$ROOT/.github/workflows/stable.yml" ]

checkout_count=$(awk '/uses: actions\/checkout@/ { count++ } END { print count + 0 }' "$CI" "$RELEASE")
persist_count=$(awk '/persist-credentials: false/ { count++ } END { print count + 0 }' "$CI" "$RELEASE")
[ "$checkout_count" -gt 0 ] && [ "$checkout_count" = "$persist_count" ]
[ "$(awk '/contents: write/ { count++ } END { print count + 0 }' "$CI" "$RELEASE")" -eq 1 ]
grep -q '^permissions:$' "$CI"
grep -q '^  contents: read$' "$CI"
grep -q 'id-token: write' "$RELEASE"
grep -q 'attestations: write' "$RELEASE"
grep -q 'attestations: read' "$RELEASE"
grep -q 'actions/attest@[0-9a-f]\{40\}' "$RELEASE"
grep -q 'actions/upload-artifact@[0-9a-f]\{40\}' "$RELEASE"
grep -q 'actions/download-artifact@[0-9a-f]\{40\}' "$RELEASE"

grep -q '^  authorize:$' "$RELEASE"
grep -q 'authorize-exact-protected-main-tag' "$RELEASE"
grep -Fq '+refs/heads/main:refs/remotes/origin/main' "$RELEASE"
grep -Fq "git cat-file -t \"refs/tags/\$GITHUB_REF_NAME\"" "$RELEASE"
grep -q 'release tags must be annotated tag objects' "$RELEASE"
grep -q 'must exactly equal the current protected origin/main HEAD' "$RELEASE"
grep -q '^    environment: firmware-signing$' "$RELEASE"
grep -q 'Materialize protected signing keys only after exact-main recheck' "$RELEASE"
grep -q 'COMPANYWRT_USIGN_CURRENT_SECRET_KEY' "$RELEASE"
authorize_line=$(grep -n 'Authorize exact protected main commit and annotated tag' "$RELEASE" | cut -d: -f1)
secret_line=$(grep -n 'PREVIOUS_USIGN_SECRET_KEY:.*secrets.COMPANYWRT_USIGN_SECRET_KEY' "$RELEASE" | cut -d: -f1)
[ "$authorize_line" -lt "$secret_line" ]

grep -Fq "production-gates/\$version.env" "$RELEASE"
grep -q 'hardware_validation=NOT_PERFORMED_RC_ONLY' "$RELEASE"
grep -q 'hardware_validation=VERIFIED' "$RELEASE"
grep -q 'production_gate_sha256=' "$RELEASE"
grep -q 'built firmware does not match the exact hardware-tested digest' "$ROOT/scripts/build-buildroot.sh"
grep -q 'Build signed Darkyun large-UBI firmware from pinned OpenWrt source' "$RELEASE"
grep -Fq -- '--profile xiaomi_ax9000_darkyun' "$RELEASE"
if grep -Fq './scripts/build-imagebuilder.sh' "$RELEASE"; then
	echo 'release workflow still invokes the incompatible standard ImageBuilder path' >&2
	exit 1
fi
grep -q 'RELEASE-MANIFEST.next.sig' "$RELEASE"
grep -q 'prerelease=(--prerelease)' "$RELEASE"
grep -q 'needs: \[build, attest\]' "$RELEASE"

grep -q -- '--draft' "$RELEASE"
grep -q -- '--draft=false' "$RELEASE"
grep -q '.immutable == true' "$RELEASE"
grep -q 'published asset digest mismatch' "$RELEASE"
grep -q "gh release verify \"\\\$GITHUB_REF_NAME\"" "$RELEASE"
grep -q 'gh release verify-asset' "$RELEASE"
grep -q "test \"\$(cat VERSION)\" = '25.12.5-company.2-rc2'" "$CI"

echo 'workflow exact-main annotated-tag authorization, protected signing, stable evidence and immutable verification: ok'
