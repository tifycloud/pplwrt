#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
CI="$ROOT/.github/workflows/ci.yml"
RELEASE="$ROOT/.github/workflows/release.yml"
[ -f "$CI" ] && [ -f "$RELEASE" ]
[ ! -f "$ROOT/.github/workflows/stable.yml" ]

checkout_count=$(grep -h 'uses: actions/checkout@' "$CI" "$RELEASE" | wc -l | tr -d '[:space:]')
persist_count=$(grep -h 'persist-credentials: false' "$CI" "$RELEASE" | wc -l | tr -d '[:space:]')
[ "$checkout_count" -gt 0 ] && [ "$checkout_count" = "$persist_count" ]
[ "$(grep -h 'contents: write' "$CI" "$RELEASE" | wc -l | tr -d '[:space:]')" = 1 ]
grep -q '^permissions:$' "$CI"
grep -q '^  contents: read$' "$CI"
grep -q 'id-token: write' "$RELEASE"
grep -q 'attestations: write' "$RELEASE"
grep -q 'actions/attest@[0-9a-f]\{40\}' "$RELEASE"
grep -q 'actions/upload-artifact@[0-9a-f]\{40\}' "$RELEASE"
grep -q 'actions/download-artifact@[0-9a-f]\{40\}' "$RELEASE"
grep -q 'tag .*must exactly match VERSION' "$RELEASE"
grep -q 'production-gates/\$version.env' "$RELEASE"
grep -q 'built firmware does not match the exact hardware-tested digest' "$RELEASE"
grep -q 'source_commit=$(git rev-parse HEAD)' "$RELEASE"
grep -q 'COMPANYWRT_USIGN_SECRET_KEY is missing' "$RELEASE"
grep -q 'prerelease=(--prerelease)' "$RELEASE"
grep -q 'needs: \[build, attest\]' "$RELEASE"
echo 'workflow least privilege, immutable pins, artifact handoff, signing/tag/stable gates: ok'
