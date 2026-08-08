#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
OUT=$("$ROOT/scripts/company-network.sh" generate --wan1 eth0.2 --wan2 eth0.3 --output "$TMP/out")
[ "$OUT" = "$TMP/out" ]
grep -q "option device 'eth0.2'" "$TMP/out/network"
grep -q "option device 'eth0.3'" "$TMP/out/network"
grep -q "option nft_file '/etc/pbr.d/company.nft'" "$TMP/out/pbr"
grep -q 'fwmark' "$TMP/out/pbr"
if "$ROOT/scripts/company-network.sh" apply --wan1 eth0.2 --wan2 eth0.3 --output "$TMP/live" 2>"$TMP/error"; then
  echo 'apply unexpectedly succeeded without --yes' >&2
  exit 1
fi
grep -q -- '--yes' "$TMP/error"
echo 'network generator: ok'
