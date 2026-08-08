#!/bin/sh
# Verify a CompanyWrt release manifest without changing router state.
set -eu

usage() { echo "Usage: ota-check.sh --manifest FILE|URL [--version VERSION] [--profile PROFILE]"; }
MANIFEST=""
EXPECTED_VERSION=""
EXPECTED_PROFILE="xiaomi_ax9000"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --manifest) MANIFEST=${2:-}; shift 2 ;;
    --version) EXPECTED_VERSION=${2:-}; shift 2 ;;
    --profile) EXPECTED_PROFILE=${2:-}; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[ -n "$MANIFEST" ] || { usage >&2; exit 2; }

TMP=""
cleanup() { [ -z "$TMP" ] || rm -f "$TMP"; }
trap cleanup EXIT INT TERM
case "$MANIFEST" in
  http://*|https://*)
    command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
    TMP=$(mktemp /tmp/companywrt-manifest.XXXXXX)
    curl -fsSL --retry 2 "$MANIFEST" -o "$TMP"
    MANIFEST="$TMP"
    ;;
esac
[ -s "$MANIFEST" ] || { echo "manifest is empty: $MANIFEST" >&2; exit 1; }

VERSION=$(awk -F= '$1=="VERSION" {print $2; exit}' "$MANIFEST")
PROFILE=$(awk -F= '$1=="PROFILE" {print $2; exit}' "$MANIFEST")
IMAGE=$(awk -F= '$1=="IMAGE" {print $2; exit}' "$MANIFEST")
SHA256=$(awk -F= '$1=="SHA256" {print $2; exit}' "$MANIFEST")
if [ -z "$VERSION" ] || [ -z "$PROFILE" ] || [ -z "$IMAGE" ] || [ -z "$SHA256" ]; then
  echo "manifest must define VERSION, PROFILE, IMAGE and SHA256" >&2; exit 1;
fi
[ -z "$EXPECTED_VERSION" ] || [ "$EXPECTED_VERSION" = "$VERSION" ] || { echo "version mismatch: $VERSION" >&2; exit 1; }
[ "$EXPECTED_PROFILE" = "$PROFILE" ] || { echo "profile mismatch: $PROFILE" >&2; exit 1; }
printf 'OTA candidate verified: VERSION=%s PROFILE=%s IMAGE=%s SHA256=%s\n' "$VERSION" "$PROFILE" "$IMAGE" "$SHA256"
