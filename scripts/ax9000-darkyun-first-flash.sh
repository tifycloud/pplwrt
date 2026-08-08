#!/bin/sh
# One-time migration gate for a verified Darkyun/KWRT AX9000. This script runs
# only read-only checks and `sysupgrade -T -F`; it never performs the flash.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/ota-common.sh"

MANIFEST=""
SIGNATURE=""
IMAGE=""
PUBLIC_KEY=""
WORK_DIR=""
EXPECTED_VERSION=""
CONFIRM_VERSION=""
CONFIRM_SHA256=""
TEST_MODE=0
TEST_SPEC=""

usage() {
	cat <<'EOF'
Usage: ax9000-darkyun-first-flash.sh --manifest FILE|HTTPS_URL \
  --public-key FILE --expected-version VERSION --confirm-version VERSION \
  --confirm-sha256 64HEX [--signature FILE] [--image FILE] [--work-dir /tmp/DIR]

This is only for the first migration from the fingerprinted Darkyun/KWRT
single-UBI layout. It verifies MIBIB/APPSBL/MTD/UBI, a committed CompanyWrt
usign trust anchor, strict manifest, image size/SHA and current board, then runs
`sysupgrade -T -F`. The final `sysupgrade -n -F` command is printed, never run.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--manifest) [ "$#" -ge 2 ] || ota_die "missing value for $1"; MANIFEST=$2; shift 2 ;;
		--signature) [ "$#" -ge 2 ] || ota_die "missing value for $1"; SIGNATURE=$2; shift 2 ;;
		--image) [ "$#" -ge 2 ] || ota_die "missing value for $1"; IMAGE=$2; shift 2 ;;
		--public-key) [ "$#" -ge 2 ] || ota_die "missing value for $1"; PUBLIC_KEY=$2; shift 2 ;;
		--work-dir) [ "$#" -ge 2 ] || ota_die "missing value for $1"; WORK_DIR=$2; shift 2 ;;
		--expected-version) [ "$#" -ge 2 ] || ota_die "missing value for $1"; EXPECTED_VERSION=$2; shift 2 ;;
		--confirm-version) [ "$#" -ge 2 ] || ota_die "missing value for $1"; CONFIRM_VERSION=$2; shift 2 ;;
		--confirm-sha256) [ "$#" -ge 2 ] || ota_die "missing value for $1"; CONFIRM_SHA256=$2; shift 2 ;;
		--test-mode) TEST_MODE=1; shift ;;
		--spec) [ "$#" -ge 2 ] || ota_die "missing value for $1"; TEST_SPEC=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; ota_die "unknown argument: $1" ;;
	esac
done

[ "$(id -u)" -eq 0 ] || ota_die 'first-flash gate requires root on the target router'
[ -n "$MANIFEST" ] && [ -n "$PUBLIC_KEY" ] || { usage >&2; exit 2; }
[ -s "$PUBLIC_KEY" ] || ota_die "public key is missing: $PUBLIC_KEY"
[ -n "$EXPECTED_VERSION" ] || ota_die '--expected-version is required'
[ "$CONFIRM_VERSION" = "$EXPECTED_VERSION" ] || ota_die 'version confirmation mismatch'
printf '%s\n' "$CONFIRM_SHA256" | grep -Eq '^[0-9a-f]{64}$' || ota_die 'exact 64-hex SHA confirmation is required'

DEVICE_ROOT=${COMPANYWRT_DEVICE_ROOT:-}
if [ "$TEST_MODE" -eq 1 ]; then
	[ "${COMPANYWRT_FIRST_FLASH_TEST_MODE:-}" = 1 ] || ota_die '--test-mode requires COMPANYWRT_FIRST_FLASH_TEST_MODE=1'
	[ -n "$TEST_SPEC" ] || ota_die '--test-mode requires --spec'
else
	[ -z "$DEVICE_ROOT" ] || ota_die 'COMPANYWRT_DEVICE_ROOT is test-only'
	[ -z "$TEST_SPEC" ] || ota_die '--spec is forbidden in production'
fi

case "$WORK_DIR" in *"'"*|*[![:print:]]*) ota_die 'work directory contains unsafe characters' ;; esac
if [ -z "$WORK_DIR" ]; then
	WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-first-flash.XXXXXX")
else
	[ ! -e "$WORK_DIR" ] && [ ! -L "$WORK_DIR" ] || ota_die 'work directory must not already exist'
	mkdir -m 0700 -- "$WORK_DIR" || ota_die 'cannot create work directory'
fi
if [ "$TEST_MODE" -eq 0 ]; then
	case "$WORK_DIR" in /tmp/*) ;; *) ota_die 'production first-flash work directory must be below /tmp' ;; esac
fi
chmod 0700 "$WORK_DIR"

PREFLIGHT_OUTPUT="$WORK_DIR/device-preflight.env"
if [ "$TEST_MODE" -eq 1 ]; then
	"$SCRIPT_DIR/ax9000-darkyun-preflight.sh" --test-mode --spec "$TEST_SPEC" --output "$PREFLIGHT_OUTPUT"
else
	"$SCRIPT_DIR/ax9000-darkyun-preflight.sh" --output "$PREFLIGHT_OUTPUT"
fi
grep -qx 'RESULT=PASS' "$PREFLIGHT_OUTPUT" || ota_die 'Darkyun hardware fingerprint preflight did not pass'

command -v usign >/dev/null 2>&1 || ota_die 'usign is required'
TRUST_KEY_ID=$(usign -F -p "$PUBLIC_KEY" 2>/dev/null) || ota_die 'invalid first-flash public key'
case "$TRUST_KEY_ID" in
	679439846de7ada5|444eb53ba66e6d45) ;;
	*) ota_die 'public key is not a committed CompanyWrt migration trust anchor' ;;
esac

OTA_DIR="$WORK_DIR/ota"
mkdir -m 0700 "$OTA_DIR"
ota_stage_and_verify "$MANIFEST" "$SIGNATURE" "$IMAGE" "$PUBLIC_KEY" "$OTA_DIR"
[ "$OTA_VERSION" = "$EXPECTED_VERSION" ] || ota_die 'candidate version does not match administrator expectation'
[ "$OTA_VERSION" = "$CONFIRM_VERSION" ] || ota_die 'candidate version changed after confirmation'
[ "$OTA_SHA256" = "$CONFIRM_SHA256" ] || ota_die 'candidate SHA256 does not match administrator confirmation'
[ "$OTA_PROFILE" = xiaomi_ax9000_darkyun ] || ota_die 'candidate profile is not the Darkyun target'
[ "$OTA_BOARD" = xiaomi,ax9000-darkyun ] || ota_die 'candidate board is not the Darkyun target'
[ "$OTA_PARTITION_VARIANT" = darkyun-large-ubi-v1 ] || ota_die 'candidate partition variant mismatch'

command -v ubus >/dev/null 2>&1 || ota_die 'ubus is required'
command -v jsonfilter >/dev/null 2>&1 || ota_die 'jsonfilter is required'
BOARD_JSON=$(ubus call system board) || ota_die 'ubus system board failed'
RUNNING_BOARD=$(printf '%s\n' "$BOARD_JSON" | jsonfilter -e '@.board_name') || ota_die 'cannot read current board'
RUNNING_TARGET=$(printf '%s\n' "$BOARD_JSON" | jsonfilter -e '@.release.target') || ota_die 'cannot read current target'
[ "$RUNNING_BOARD" = "$OTA_MIGRATION_BOARD" ] || ota_die "current board is not the declared migration board: $RUNNING_BOARD"
case "$RUNNING_TARGET" in ipq807x/generic|qualcommax/ipq807x) ;; *) ota_die "unexpected current target: $RUNNING_TARGET" ;; esac

command -v sysupgrade >/dev/null 2>&1 || ota_die 'sysupgrade is required'
printf 'Running forced compatibility test only: sysupgrade -T -F %s\n' "$OTA_STAGED_IMAGE"
sysupgrade -T -F "$OTA_STAGED_IMAGE" || ota_die 'sysupgrade force-test rejected the custom image'

printf '\nFIRST-FLASH CANDIDATE PASSED ALL AUTOMATED GATES\n'
printf 'Hardware evidence: %s\n' "$PREFLIGHT_OUTPUT"
printf 'Candidate: VERSION=%s SHA256=%s PROFILE=%s BOARD=%s\n' "$OTA_VERSION" "$OTA_SHA256" "$OTA_PROFILE" "$OTA_BOARD"
printf 'No flash command was executed. Preserve rescue access, use wired LAN and stable power, then make a separate on-site decision.\n'
printf "Final manual command (NOT executed): sysupgrade -n -F '%s'\n" "$OTA_STAGED_IMAGE"
