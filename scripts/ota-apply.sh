#!/bin/sh
# Re-verify a signed OTA bundle against this router, run sysupgrade -T, and
# print (never execute) the final manual sysupgrade command.
set -eu

SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname "$0")" && pwd)
# Installed beside this script in the image.
# shellcheck disable=SC1091
. "$SCRIPT_DIR/ota-common.sh"

usage() {
	cat <<'EOF'
Usage: ota-apply.sh --manifest FILE|HTTPS_URL --expected-version VERSION \
  --expected-channel rc|beta|stable --confirm-version VERSION \
  --confirm-sha256 64HEX [options]

Options:
  --signature FILE|HTTPS_URL   Override SIGNATURE_URL for an offline bundle
  --image FILE|HTTPS_URL       Override URL for an offline bundle
  --work-dir DIR               Secure staging directory
  --test-mode                  TEST AUTOMATION ONLY; never use on a router

PRODUCTION TRUST ANCHOR IS FIXED:
  /etc/companywrt/keys/release.pub

  --public-key FILE is forbidden in production. It is accepted only together
  with --test-mode, COMPANYWRT_OTA_TEST_MODE=1 and a temporary
  COMPANYWRT_DEVICE_ROOT. This escape hatch exists solely for automated tests.

This command requires root and a real xiaomi,ax9000. It re-downloads/copies and
re-verifies the manifest, usign signature/key id, image size/SHA, profile,
board, OpenWrt release, installed build metadata, expected version/channel and
both administrator confirmations. It runs only `sysupgrade -T`; final flashing
is printed for a separate on-site manual decision.
EOF
}

MANIFEST=""
SIGNATURE=""
IMAGE=""
PUBLIC_KEY="/etc/companywrt/keys/release.pub"
PUBLIC_KEY_OVERRIDE=""
WORK_DIR=""
TEST_MODE=0
EXPECTED_VERSION=""
EXPECTED_CHANNEL=""
CONFIRM_VERSION=""
CONFIRM_SHA256=""

while [ "$#" -gt 0 ]; do
	case "$1" in
		--manifest) [ "$#" -ge 2 ] || ota_die "missing value for $1"; MANIFEST=$2; shift 2 ;;
		--signature) [ "$#" -ge 2 ] || ota_die "missing value for $1"; SIGNATURE=$2; shift 2 ;;
		--image) [ "$#" -ge 2 ] || ota_die "missing value for $1"; IMAGE=$2; shift 2 ;;
		--public-key) [ "$#" -ge 2 ] || ota_die "missing value for $1"; PUBLIC_KEY_OVERRIDE=$2; shift 2 ;;
		--test-mode) TEST_MODE=1; shift ;;
		--work-dir) [ "$#" -ge 2 ] || ota_die "missing value for $1"; WORK_DIR=$2; shift 2 ;;
		--expected-version) [ "$#" -ge 2 ] || ota_die "missing value for $1"; EXPECTED_VERSION=$2; shift 2 ;;
		--expected-channel) [ "$#" -ge 2 ] || ota_die "missing value for $1"; EXPECTED_CHANNEL=$2; shift 2 ;;
		--confirm-version) [ "$#" -ge 2 ] || ota_die "missing value for $1"; CONFIRM_VERSION=$2; shift 2 ;;
		--confirm-sha256) [ "$#" -ge 2 ] || ota_die "missing value for $1"; CONFIRM_SHA256=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; ota_die "unknown argument: $1" ;;
	esac
done

DEVICE_ROOT=${COMPANYWRT_DEVICE_ROOT:-}
if [ "$TEST_MODE" -eq 1 ]; then
	[ "${COMPANYWRT_OTA_TEST_MODE:-}" = 1 ] || ota_die "--test-mode requires COMPANYWRT_OTA_TEST_MODE=1"
	case "$DEVICE_ROOT" in /*) ;; *) ota_die "--test-mode requires an absolute COMPANYWRT_DEVICE_ROOT" ;; esac
	if [ ! -d "$DEVICE_ROOT" ] || [ -L "$DEVICE_ROOT" ]; then
		ota_die "--test-mode device root must be a real directory"
	fi
	test_parent=$(realpath "${TMPDIR:-/tmp}") || ota_die "cannot resolve temporary directory"
	test_device_root=$(realpath "$DEVICE_ROOT") || ota_die "cannot resolve test device root"
	case "$test_device_root" in "$test_parent"/*) ;; *) ota_die "--test-mode device root must be below the process temporary directory" ;; esac
	if [ -n "$PUBLIC_KEY_OVERRIDE" ]; then
		PUBLIC_KEY=$PUBLIC_KEY_OVERRIDE
	else
		PUBLIC_KEY="$DEVICE_ROOT/etc/companywrt/keys/release.pub"
	fi
else
	[ -z "$PUBLIC_KEY_OVERRIDE" ] || ota_die "--public-key is forbidden in production; the built-in release.pub is mandatory"
	[ -z "$DEVICE_ROOT" ] || ota_die "COMPANYWRT_DEVICE_ROOT is test-only and requires explicit --test-mode"
	PUBLIC_KEY=/etc/companywrt/keys/release.pub
fi

[ "$(id -u)" -eq 0 ] || ota_die "ota-apply requires root on the target router"
[ -n "$MANIFEST" ] || { usage >&2; exit 2; }
[ -n "$EXPECTED_VERSION" ] || ota_die "--expected-version is required"
case "$EXPECTED_CHANNEL" in rc|beta|stable) ;; *) ota_die "--expected-channel must be rc, beta or stable" ;; esac
[ "$CONFIRM_VERSION" = "$EXPECTED_VERSION" ] || ota_die "first confirmation must exactly match --expected-version"
printf '%s\n' "$CONFIRM_SHA256" | grep -Eq '^[0-9a-f]{64}$' || ota_die "second confirmation must be an exact 64-hex SHA256"

case "$WORK_DIR" in *"'"*|*[![:print:]]*) ota_die "work directory contains unsafe characters" ;; esac
if [ -z "$WORK_DIR" ]; then
	WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-ota-apply.XXXXXX")
else
	if [ -e "$WORK_DIR" ] || [ -L "$WORK_DIR" ]; then
		ota_die "work directory must not already exist"
	fi
	mkdir -m 0700 -- "$WORK_DIR" || ota_die "cannot create work directory: $WORK_DIR"
fi

# This is deliberately a fresh verification pass even if ota-check succeeded.
ota_stage_and_verify "$MANIFEST" "$SIGNATURE" "$IMAGE" "$PUBLIC_KEY" "$WORK_DIR"
[ "$OTA_VERSION" = "$EXPECTED_VERSION" ] || ota_die "candidate version does not match administrator expectation"
[ "$OTA_CHANNEL" = "$EXPECTED_CHANNEL" ] || ota_die "candidate channel does not match administrator expectation"
[ "$OTA_VERSION" = "$CONFIRM_VERSION" ] || ota_die "candidate version changed after confirmation"
[ "$OTA_SHA256" = "$CONFIRM_SHA256" ] || ota_die "candidate SHA256 does not match second confirmation"
[ "$OTA_PROFILE" = xiaomi_ax9000 ] || ota_die "unsupported candidate profile: $OTA_PROFILE"
[ "$OTA_BOARD" = xiaomi,ax9000 ] || ota_die "unsupported candidate board: $OTA_BOARD"

command -v ubus >/dev/null 2>&1 || ota_die "ubus is required on the target router"
command -v jsonfilter >/dev/null 2>&1 || ota_die "jsonfilter is required on the target router"
board_json=$(ubus call system board) || ota_die "ubus system board failed"
device_board=$(printf '%s\n' "$board_json" | jsonfilter -e '@.board_name') || ota_die "cannot read board_name"
device_release=$(printf '%s\n' "$board_json" | jsonfilter -e '@.release.version') || ota_die "cannot read OpenWrt release"
device_target=$(printf '%s\n' "$board_json" | jsonfilter -e '@.release.target') || ota_die "cannot read OpenWrt target"
[ "$device_board" = "$OTA_BOARD" ] || ota_die "device board mismatch: expected $OTA_BOARD, got $device_board"
[ "$device_release" = "$OTA_OPENWRT_RELEASE" ] || ota_die "OpenWrt release mismatch: expected $OTA_OPENWRT_RELEASE, got $device_release"
[ "$device_target" = qualcommax/ipq807x ] || ota_die "unsupported device target: $device_target"

BUILD_CONF="$DEVICE_ROOT/etc/companywrt/build.conf"
INSTALLED_VERSION_FILE="$DEVICE_ROOT/etc/companywrt/VERSION"
[ -s "$BUILD_CONF" ] || ota_die "installed build metadata is missing: $BUILD_CONF"
[ -s "$INSTALLED_VERSION_FILE" ] || ota_die "installed version is missing: $INSTALLED_VERSION_FILE"
installed_profile=$(awk -F= '$1 == "PROFILE" { print $2; exit }' "$BUILD_CONF")
installed_channel=$(awk -F= '$1 == "CHANNEL" { print $2; exit }' "$BUILD_CONF")
installed_version=$(sed -n '1p' "$INSTALLED_VERSION_FILE")
[ "$installed_profile" = "$OTA_PROFILE" ] || ota_die "installed profile does not match candidate profile"
case "$installed_channel" in rc|beta|stable) ;; *) ota_die "installed channel metadata is invalid" ;; esac
printf '%s\n' "$installed_version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-company\.[0-9]+(-(rc|beta)[1-9][0-9]*)?$' || ota_die "installed version metadata is invalid"
[ "$installed_version" != "$OTA_VERSION" ] || ota_die "refusing an unreviewed reinstall of the currently installed version"
installed_generation=$(printf '%s\n' "$installed_version" | sed -n 's/.*-company\.\([0-9][0-9]*\).*/\1/p')
candidate_generation=$(printf '%s\n' "$OTA_VERSION" | sed -n 's/.*-company\.\([0-9][0-9]*\).*/\1/p')
[ "${installed_version%%-company.*}" = "$device_release" ] || ota_die "installed VERSION base does not match the running OpenWrt release"
case "$installed_channel" in
	rc) printf '%s\n' "$installed_version" | grep -Eq -- '-rc[1-9][0-9]*$' || ota_die "installed VERSION suffix does not match installed CHANNEL" ;;
	beta) printf '%s\n' "$installed_version" | grep -Eq -- '-beta[1-9][0-9]*$' || ota_die "installed VERSION suffix does not match installed CHANNEL" ;;
	stable) printf '%s\n' "$installed_version" | grep -Eq -- '-company\.[0-9]+$' || ota_die "installed VERSION suffix does not match installed CHANNEL" ;;
esac
[ "$candidate_generation" -ge "$installed_generation" ] 2>/dev/null || ota_die "candidate is an older CompanyWrt generation"
if [ "$candidate_generation" -eq "$installed_generation" ]; then
	case "$installed_version" in
		*-beta*) installed_stage=0; installed_stage_number=${installed_version##*-beta} ;;
		*-rc*) installed_stage=1; installed_stage_number=${installed_version##*-rc} ;;
		*) installed_stage=2; installed_stage_number=0 ;;
	esac
	case "$OTA_VERSION" in
		*-beta*) candidate_stage=0; candidate_stage_number=${OTA_VERSION##*-beta} ;;
		*-rc*) candidate_stage=1; candidate_stage_number=${OTA_VERSION##*-rc} ;;
		*) candidate_stage=2; candidate_stage_number=0 ;;
	esac
	if [ "$candidate_stage" -lt "$installed_stage" ] || {
		[ "$candidate_stage" -eq "$installed_stage" ] &&
		[ "$candidate_stage_number" -le "$installed_stage_number" ];
	}; then
		ota_die "candidate is not newer than the installed CompanyWrt prerelease/stable stage"
	fi
fi
if [ "$installed_channel" = stable ] && [ "$OTA_CHANNEL" != stable ]; then
	ota_die "stable installations cannot move to a prerelease channel"
fi

command -v sysupgrade >/dev/null 2>&1 || ota_die "sysupgrade is required on the target router"
printf 'Running read-only platform validation: sysupgrade -T %s\n' "$OTA_IMAGE"
sysupgrade -T "$OTA_STAGED_IMAGE" || ota_die "sysupgrade -T rejected the image"

printf '\nSIGNED OTA CANDIDATE PASSED ALL AUTOMATED CHECKS\n'
printf 'Installed: VERSION=%s CHANNEL=%s PROFILE=%s BOARD=%s\n' "$installed_version" "$installed_channel" "$installed_profile" "$device_board"
printf 'Candidate: VERSION=%s CHANNEL=%s SHA256=%s SIZE=%s\n' "$OTA_VERSION" "$OTA_CHANNEL" "$OTA_SHA256" "$OTA_SIZE"
printf 'No flash was performed. Back up configuration/logs, verify boot slot and recovery evidence, then make a separate on-site decision.\n'
printf "Final manual command (NOT executed): sysupgrade '%s'\n" "$OTA_STAGED_IMAGE"
