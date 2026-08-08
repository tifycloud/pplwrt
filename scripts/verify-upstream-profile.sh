#!/bin/sh
# Fetch first-party metadata and compare the checked-in profile. Read-only.
set -eu
ROOT=$(cd -P -- "$(dirname "$0")/.." && pwd)
command -v curl >/dev/null 2>&1 || { echo 'curl is required' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'jq is required' >&2; exit 1; }
BASE='https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x'
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-upstream.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
curl -fsSL "$BASE/profiles.json" -o "$TMP/profiles.json"
curl -fsSL "$BASE/sha256sums" -o "$TMP/sha256sums"
[ "$(jq -r '.profiles.xiaomi_ax9000.supported_devices[0]' "$TMP/profiles.json")" = "$(jq -r '.supported_devices[0]' "$ROOT/devices/ax9000/profile.json")" ]
[ "$(jq -r '.profiles.xiaomi_ax9000.image_prefix' "$TMP/profiles.json")" = "$(jq -r '.image_prefix' "$ROOT/devices/ax9000/profile.json")" ]
IB=$(jq -r '.imagebuilder.filename' "$ROOT/devices/ax9000/profile.json")
IBSHA=$(jq -r '.imagebuilder.sha256' "$ROOT/devices/ax9000/profile.json")
awk -v sha="$IBSHA" -v name="*$IB" '$1 == sha && $2 == name {ok=1} END {exit !ok}' "$TMP/sha256sums"
echo 'upstream standard-layout profile reference and ImageBuilder checksum: ok'
