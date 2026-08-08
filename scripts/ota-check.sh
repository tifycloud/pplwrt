#!/bin/sh
# Download and cryptographically verify a complete CompanyWrt OTA candidate.
# This command never calls sysupgrade or changes UCI/device state.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# Installed beside this script in the image.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/ota-common.sh"

usage() {
	cat <<'EOF'
Usage: ota-check.sh --manifest FILE|HTTPS_URL [options]

Options:
  --signature FILE|HTTPS_URL   Override manifest SIGNATURE_URL (offline bundle)
  --image FILE|HTTPS_URL       Override manifest URL (offline bundle)
  --public-key FILE            Trusted usign public key
  --download-dir DIR           Preserve verified bundle here
  --version VERSION            Require exact candidate version
  --profile PROFILE            Require exact profile (default xiaomi_ax9000)
  --board BOARD                Require exact board (default xiaomi,ax9000)
  --channel rc|beta|stable     Require exact release channel

Remote inputs are HTTPS-only. The manifest schema, usign signature/key id,
actual downloaded image size and 64-hex SHA256 are all mandatory.
Stable candidates additionally require a v2 manifest that binds the exact
hardware evidence file digest, opaque evidence IDs and tested firmware SHA.
EOF
}

MANIFEST=""
SIGNATURE=""
IMAGE=""
PUBLIC_KEY="/etc/companywrt/keys/release.pub"
DOWNLOAD_DIR=""
EXPECTED_VERSION=""
EXPECTED_PROFILE="xiaomi_ax9000"
EXPECTED_BOARD="xiaomi,ax9000"
EXPECTED_CHANNEL=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		--manifest) [ "$#" -ge 2 ] || ota_die "missing value for $1"; MANIFEST=$2; shift 2 ;;
		--signature) [ "$#" -ge 2 ] || ota_die "missing value for $1"; SIGNATURE=$2; shift 2 ;;
		--image) [ "$#" -ge 2 ] || ota_die "missing value for $1"; IMAGE=$2; shift 2 ;;
		--public-key) [ "$#" -ge 2 ] || ota_die "missing value for $1"; PUBLIC_KEY=$2; shift 2 ;;
		--download-dir) [ "$#" -ge 2 ] || ota_die "missing value for $1"; DOWNLOAD_DIR=$2; shift 2 ;;
		--version) [ "$#" -ge 2 ] || ota_die "missing value for $1"; EXPECTED_VERSION=$2; shift 2 ;;
		--profile) [ "$#" -ge 2 ] || ota_die "missing value for $1"; EXPECTED_PROFILE=$2; shift 2 ;;
		--board) [ "$#" -ge 2 ] || ota_die "missing value for $1"; EXPECTED_BOARD=$2; shift 2 ;;
		--channel) [ "$#" -ge 2 ] || ota_die "missing value for $1"; EXPECTED_CHANNEL=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; ota_die "unknown argument: $1" ;;
	esac
done

[ -n "$MANIFEST" ] || { usage >&2; exit 2; }
case "$DOWNLOAD_DIR" in *"'"*|*[![:print:]]*) ota_die "download directory contains unsafe characters" ;; esac
if [ -z "$DOWNLOAD_DIR" ]; then
	DOWNLOAD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-ota-check.XXXXXX")
else
	if [ -e "$DOWNLOAD_DIR" ] || [ -L "$DOWNLOAD_DIR" ]; then
		ota_die "download directory must not already exist"
	fi
	mkdir -m 0700 -- "$DOWNLOAD_DIR" || ota_die "cannot create download directory: $DOWNLOAD_DIR"
fi

ota_stage_and_verify "$MANIFEST" "$SIGNATURE" "$IMAGE" "$PUBLIC_KEY" "$DOWNLOAD_DIR"
[ -z "$EXPECTED_VERSION" ] || [ "$OTA_VERSION" = "$EXPECTED_VERSION" ] || ota_die "version mismatch: expected $EXPECTED_VERSION, got $OTA_VERSION"
[ "$OTA_PROFILE" = "$EXPECTED_PROFILE" ] || ota_die "profile mismatch: expected $EXPECTED_PROFILE, got $OTA_PROFILE"
[ "$OTA_BOARD" = "$EXPECTED_BOARD" ] || ota_die "board mismatch: expected $EXPECTED_BOARD, got $OTA_BOARD"
[ -z "$EXPECTED_CHANNEL" ] || [ "$OTA_CHANNEL" = "$EXPECTED_CHANNEL" ] || ota_die "channel mismatch: expected $EXPECTED_CHANNEL, got $OTA_CHANNEL"

printf 'VERIFIED_VERSION=%s\n' "$OTA_VERSION"
printf 'VERIFIED_PROFILE=%s\n' "$OTA_PROFILE"
printf 'VERIFIED_BOARD=%s\n' "$OTA_BOARD"
printf 'VERIFIED_CHANNEL=%s\n' "$OTA_CHANNEL"
printf 'VERIFIED_IMAGE=%s\n' "$OTA_STAGED_IMAGE"
printf 'VERIFIED_SHA256=%s\n' "$OTA_SHA256"
printf 'VERIFIED_SIZE=%s\n' "$OTA_SIZE"
printf 'VERIFIED_HARDWARE_VALIDATION=%s\n' "$OTA_HARDWARE_VALIDATION"
printf 'VERIFIED_PRODUCTION_GATE_SHA256=%s\n' "$OTA_PRODUCTION_GATE_SHA256"
printf 'No router state was changed. Run ota-apply separately on the target router; it re-verifies everything.\n'
