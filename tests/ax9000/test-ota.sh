#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-ota.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
cat > "$TMP/manifest" <<'EOF'
VERSION=25.12.5-company.1
PROFILE=xiaomi_ax9000
IMAGE=test.bin
SHA256=0123456789abcdef
EOF
"$ROOT/scripts/ota-check.sh" --manifest "$TMP/manifest" --version 25.12.5-company.1
if "$ROOT/scripts/ota-check.sh" --manifest "$TMP/manifest" --profile wrong >"$TMP/out" 2>&1; then
  echo 'profile mismatch unexpectedly passed' >&2
  exit 1
fi
echo 'ota manifest: ok'
