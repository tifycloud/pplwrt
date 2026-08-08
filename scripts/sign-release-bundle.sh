#!/bin/sh
# Convert a verified unsigned Buildroot bundle into a signed release bundle.
# This script never compiles firmware. It is intended for the isolated
# firmware-signing environment after the no-secret build job has completed.
set -eu

CALLER_DIR=$(pwd -P)
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
INPUT=""
OUTPUT=""
CHANNEL=""
SIGNING_KEY=${USIGN_SECRET_KEY_FILE:-}
CURRENT_SIGNING_KEY=${USIGN_CURRENT_SECRET_KEY_FILE:-}
RELEASE_BASE_URL=""
VERSION=$(sed -n '1p' "$ROOT/VERSION")

usage() {
	cat <<'EOF'
Usage: sign-release-bundle.sh --input DIR --channel stable|rc|beta [options]
  --output DIR
  --signing-key FILE
  --current-signing-key FILE
  --release-base-url HTTPS_URL

The input must be an untouched --compile-only Buildroot output whose
SHA256SUMS and content report pass. Private keys must be outside the repository.
No compiler, make, network download or firmware mutation is performed here.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--input) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; INPUT=$2; shift 2 ;;
		--output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; OUTPUT=$2; shift 2 ;;
		--channel) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; CHANNEL=$2; shift 2 ;;
		--signing-key) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; SIGNING_KEY=$2; shift 2 ;;
		--current-signing-key) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; CURRENT_SIGNING_KEY=$2; shift 2 ;;
		--release-base-url) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; RELEASE_BASE_URL=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
	esac
done

[ -n "$INPUT" ] && [ -n "$CHANNEL" ] || { usage >&2; exit 2; }
case "$CHANNEL" in stable|rc|beta) ;; *) echo 'channel must be stable, rc or beta' >&2; exit 2 ;; esac
case "$CHANNEL" in
	rc) printf '%s\n' "$VERSION" | grep -Eq -- '-rc[1-9][0-9]*$' || { echo 'rc channel requires an -rcN VERSION' >&2; exit 1; } ;;
	beta) printf '%s\n' "$VERSION" | grep -Eq -- '-beta[1-9][0-9]*$' || { echo 'beta channel requires a -betaN VERSION' >&2; exit 1; } ;;
	stable) printf '%s\n' "$VERSION" | grep -Eq -- '-(rc|beta)[1-9][0-9]*$' && { echo 'stable channel cannot sign a prerelease VERSION' >&2; exit 1; } ;;
esac
case "$INPUT" in /*) ;; *) INPUT="$CALLER_DIR/$INPUT" ;; esac
if [ -z "$OUTPUT" ]; then OUTPUT="$ROOT/artifacts/$CHANNEL/$VERSION"; fi
case "$OUTPUT" in /*) ;; *) OUTPUT="$CALLER_DIR/$OUTPUT" ;; esac
[ -d "$INPUT" ] && [ ! -L "$INPUT" ] || { echo 'unsigned input must be a real directory' >&2; exit 1; }
[ ! -e "$OUTPUT" ] && [ ! -L "$OUTPUT" ] || { echo "refusing existing output directory: $OUTPUT" >&2; exit 1; }
[ -s "$INPUT/COMPILE-ONLY-NOT-A-RELEASE.txt" ] || { echo 'unsigned compile-only marker is missing' >&2; exit 1; }
[ -s "$INPUT/SHA256SUMS" ] || { echo 'unsigned bundle checksums are missing' >&2; exit 1; }
if find "$INPUT" -maxdepth 1 -type f -name 'RELEASE-MANIFEST*' -print -quit | grep -q .; then
	echo 'unsigned input unexpectedly contains a release manifest/signature' >&2
	exit 1
fi
(cd "$INPUT" && sha256sum -c SHA256SUMS)

metadata_value() {
	key=$1
	awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); count++ } END { if (count != 1) exit 1 }' "$INPUT/BUILD-METADATA"
}
[ -s "$INPUT/BUILD-METADATA" ] || { echo 'unsigned build metadata is missing' >&2; exit 1; }
[ "$(metadata_value version)" = "$VERSION" ] || { echo 'unsigned VERSION mismatch' >&2; exit 1; }
[ "$(metadata_value channel)" = "$CHANNEL" ] || { echo 'unsigned channel mismatch' >&2; exit 1; }
[ "$(metadata_value profile)" = xiaomi_ax9000_darkyun ] || { echo 'unsigned profile mismatch' >&2; exit 1; }
[ "$(metadata_value board)" = xiaomi,ax9000-darkyun ] || { echo 'unsigned board mismatch' >&2; exit 1; }
[ "$(metadata_value partition_variant)" = darkyun-large-ubi-v1 ] || { echo 'unsigned partition variant mismatch' >&2; exit 1; }
[ "$(metadata_value openwrt_release)" = 25.12.5 ] || { echo 'unsigned OpenWrt release mismatch' >&2; exit 1; }
[ "$(metadata_value openwrt_commit)" = f0a60eee2fe051741c643ea6118718aae1ef17fb ] || { echo 'unsigned OpenWrt commit mismatch' >&2; exit 1; }
[ "$(metadata_value build_system)" = full-openwrt-buildroot ] || { echo 'unsigned build system mismatch' >&2; exit 1; }
[ "$(metadata_value release_signing)" = NOT_PERFORMED_COMPILE_ONLY ] || { echo 'input was not produced by the no-secret compile path' >&2; exit 1; }
SOURCE_COMMIT=$(metadata_value source_commit)
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || { echo 'unsigned source commit is invalid' >&2; exit 1; }
if git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
	[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SOURCE_COMMIT" ] || { echo 'unsigned source commit does not equal signing checkout HEAD' >&2; exit 1; }
fi

HARDWARE_VALIDATION=$(metadata_value hardware_validation)
PRODUCTION_GATE_SHA256=NONE
HARDWARE_EVIDENCE_ID=NONE
SERIAL_EVIDENCE_ID=NONE
TESTED_FIRMWARE_SHA256=NONE
if [ "$CHANNEL" = stable ]; then
	[ "$HARDWARE_VALIDATION" = VERIFIED ] || { echo 'stable unsigned bundle lacks verified hardware evidence' >&2; exit 1; }
	PRODUCTION_GATE="$ROOT/production-gates/$VERSION.env"
	[ -s "$PRODUCTION_GATE" ] || { echo 'stable production evidence is missing' >&2; exit 1; }
	"$ROOT/scripts/verify-production-gate.sh" "$PRODUCTION_GATE" "$VERSION"
	PRODUCTION_GATE_SHA256=$(sha256sum "$PRODUCTION_GATE" | awk '{print $1}')
	HARDWARE_EVIDENCE_ID=$(awk -F= '$1 == "HARDWARE_EVIDENCE_ID" { print $2; exit }' "$PRODUCTION_GATE")
	SERIAL_EVIDENCE_ID=$(awk -F= '$1 == "SERIAL_EVIDENCE_ID" { print $2; exit }' "$PRODUCTION_GATE")
	TESTED_FIRMWARE_SHA256=$(awk -F= '$1 == "FIRMWARE_SHA256" { print $2; exit }' "$PRODUCTION_GATE")
	[ "$(metadata_value production_gate_sha256)" = "$PRODUCTION_GATE_SHA256" ] || { echo 'unsigned production evidence digest mismatch' >&2; exit 1; }
	[ "$(metadata_value tested_firmware_sha256)" = "$TESTED_FIRMWARE_SHA256" ] || { echo 'unsigned tested firmware digest mismatch' >&2; exit 1; }
else
	[ "$HARDWARE_VALIDATION" = NOT_PERFORMED_RC_ONLY ] || { echo 'prerelease input carries an invalid hardware status' >&2; exit 1; }
fi

IMAGE=$(find "$INPUT" -maxdepth 1 -type f -name '*-sysupgrade.bin' -print)
[ "$(printf '%s\n' "$IMAGE" | sed '/^$/d' | wc -l | tr -d '[:space:]')" -eq 1 ] || { echo 'unsigned bundle must contain exactly one sysupgrade image' >&2; exit 1; }
IMAGE_NAME=${IMAGE##*/}
IMAGE_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
IMAGE_SIZE=$(wc -c < "$IMAGE" | tr -d '[:space:]')
[ "$HARDWARE_VALIDATION" != VERIFIED ] || [ "$IMAGE_SHA" = "$TESTED_FIRMWARE_SHA256" ] || { echo 'stable unsigned image differs from hardware-tested digest' >&2; exit 1; }
grep -qx "image_sha256=$IMAGE_SHA" "$INPUT/FIRMWARE-CONTENT-REPORT.txt" || { echo 'content report is not bound to the unsigned image' >&2; exit 1; }
grep -qx 'kernel_dtb_layout=PASS' "$INPUT/FIRMWARE-CONTENT-REPORT.txt" || { echo 'kernel DTB inspection did not pass' >&2; exit 1; }
grep -qx 'partition_variant=darkyun-large-ubi-v1' "$INPUT/FIRMWARE-CONTENT-REPORT.txt" || { echo 'content report partition mismatch' >&2; exit 1; }
[ "$(wc -l < "$INPUT/PACKAGE-MANIFEST" | tr -d '[:space:]')" -eq 251 ] || { echo 'unsigned package manifest count mismatch' >&2; exit 1; }

HOST_USIGN_ARCHIVE="$INPUT/BUILD-HOST-USIGN.tar.zst"
[ -f "$HOST_USIGN_ARCHIVE" ] && [ ! -L "$HOST_USIGN_ARCHIVE" ] || { echo 'verified Buildroot host usign archive is missing' >&2; exit 1; }
HOST_TOOL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-usign-tool.XXXXXX")
OUTPUT_WORK=""
cleanup() {
	[ ! -d "$HOST_TOOL_DIR" ] || rm -rf "$HOST_TOOL_DIR"
	[ -z "$OUTPUT_WORK" ] || [ ! -d "$OUTPUT_WORK" ] || rm -rf "$OUTPUT_WORK"
}
trap cleanup EXIT INT TERM
tar tf "$HOST_USIGN_ARCHIVE" > "$HOST_TOOL_DIR/archive.list" || { echo 'cannot list host usign archive' >&2; exit 1; }
awk '/^\// || /(^|\/)\.\.($|\/)/ { exit 1 }' "$HOST_TOOL_DIR/archive.list" || { echo 'unsafe path in host usign archive' >&2; exit 1; }
tar --zstd -xf "$HOST_USIGN_ARCHIVE" -C "$HOST_TOOL_DIR"
USIGN_BIN="$HOST_TOOL_DIR/bin/usign"
[ -f "$USIGN_BIN" ] && [ ! -L "$USIGN_BIN" ] && [ -x "$USIGN_BIN" ] || { echo 'verified Buildroot host usign executable is missing' >&2; exit 1; }
ROOT_REAL=$(realpath "$ROOT")
validate_secret() {
	secret=$1
	description=$2
	[ -s "$secret" ] || { echo "$description is required" >&2; exit 1; }
	secret_real=$(realpath "$secret")
	case "$secret_real" in "$ROOT_REAL"/*) echo "$description must be outside the repository" >&2; exit 1 ;; esac
}
validate_secret "$SIGNING_KEY" 'manifest signing key'

ROTATION_FILE="$ROOT/keys/ROTATION.env"
rotation_value() { awk -F= -v wanted="$1" '$1 == wanted { print $2; exit }' "$ROTATION_FILE"; }
TRANSITION_VERSION=$(rotation_value TRANSITION_VERSION)
PREVIOUS_PUBLIC_KEY="$ROOT/$(rotation_value PREVIOUS_PUBLIC_KEY)"
CURRENT_PUBLIC_KEY="$ROOT/$(rotation_value CURRENT_PUBLIC_KEY)"
PREVIOUS_KEY_ID=$(rotation_value PREVIOUS_KEY_ID)
CURRENT_KEY_ID=$(rotation_value CURRENT_KEY_ID)
KEY_TRANSITION=0
MANIFEST_PUBLIC_KEY=$CURRENT_PUBLIC_KEY
if [ "$VERSION" = "$TRANSITION_VERSION" ]; then
	KEY_TRANSITION=1
	MANIFEST_PUBLIC_KEY=$PREVIOUS_PUBLIC_KEY
	validate_secret "$CURRENT_SIGNING_KEY" 'current rotation signing key'
elif [ -n "$CURRENT_SIGNING_KEY" ]; then
	echo 'current rotation key is valid only for the declared transition version' >&2
	exit 1
fi
MANIFEST_PUBLIC_KEY_ID=$("$USIGN_BIN" -F -p "$MANIFEST_PUBLIC_KEY")
EMBEDDED_PUBLIC_KEY_ID=$("$USIGN_BIN" -F -p "$CURRENT_PUBLIC_KEY")
[ "$EMBEDDED_PUBLIC_KEY_ID" = "$CURRENT_KEY_ID" ] || { echo 'current public key ID mismatch' >&2; exit 1; }
[ "$("$USIGN_BIN" -F -p "$PREVIOUS_PUBLIC_KEY")" = "$PREVIOUS_KEY_ID" ] || { echo 'previous public key ID mismatch' >&2; exit 1; }
[ "$("$USIGN_BIN" -F -s "$SIGNING_KEY")" = "$MANIFEST_PUBLIC_KEY_ID" ] || { echo 'manifest private key mismatch' >&2; exit 1; }
if [ "$KEY_TRANSITION" -eq 1 ]; then
	[ "$MANIFEST_PUBLIC_KEY_ID" = "$PREVIOUS_KEY_ID" ] || { echo 'transition primary key mismatch' >&2; exit 1; }
	[ "$("$USIGN_BIN" -F -s "$CURRENT_SIGNING_KEY")" = "$CURRENT_KEY_ID" ] || { echo 'transition current private key mismatch' >&2; exit 1; }
else
	[ "$MANIFEST_PUBLIC_KEY_ID" = "$CURRENT_KEY_ID" ] || { echo 'non-transition manifest key mismatch' >&2; exit 1; }
fi

if [ -z "$RELEASE_BASE_URL" ]; then RELEASE_BASE_URL="https://github.com/tifycloud/pplwrt/releases/download/v$VERSION"; fi
case "$RELEASE_BASE_URL" in https://*) ;; *) echo 'release base URL must use HTTPS' >&2; exit 1 ;; esac
case "$RELEASE_BASE_URL" in *[!A-Za-z0-9._~:/%-]*) echo 'release base URL contains unsupported characters' >&2; exit 1 ;; esac

OUTPUT_PARENT=$(dirname "$OUTPUT")
mkdir -p "$OUTPUT_PARENT"
OUTPUT_WORK=$(mktemp -d "$OUTPUT_PARENT/.companywrt-sign-$VERSION.XXXXXX")
cp -a "$INPUT/." "$OUTPUT_WORK/"
rm -f "$OUTPUT_WORK/COMPILE-ONLY-NOT-A-RELEASE.txt" "$OUTPUT_WORK/BUILD-METADATA" \
	"$OUTPUT_WORK/SHA256SUMS" "$OUTPUT_WORK/BUILD-HOST-USIGN.tar.zst"

SIGNATURE_NAME=RELEASE-MANIFEST.sig
{
	if [ "$HARDWARE_VALIDATION" = VERIFIED ]; then printf 'FORMAT=companywrt-darkyun-release-v2\n'; else printf 'FORMAT=companywrt-darkyun-release-v1\n'; fi
	printf 'VERSION=%s\nOPENWRT_RELEASE=25.12.5\nPROFILE=xiaomi_ax9000_darkyun\nBOARD=xiaomi,ax9000-darkyun\n' "$VERSION"
	printf 'PARTITION_VARIANT=darkyun-large-ubi-v1\n'
	printf 'MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11\n'
	printf 'APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007\n'
	printf 'MIGRATION_BOARD=xiaomi,ax9000\nCHANNEL=%s\nTAG=v%s\nSOURCE_COMMIT=%s\n' "$CHANNEL" "$VERSION" "$SOURCE_COMMIT"
	printf 'IMAGE=%s\nSHA256=%s\nSIZE=%s\nURL=%s/%s\n' "$IMAGE_NAME" "$IMAGE_SHA" "$IMAGE_SIZE" "$RELEASE_BASE_URL" "$IMAGE_NAME"
	printf 'SIGNATURE=%s\nSIGNATURE_URL=%s/%s\nUSIGN_KEY_ID=%s\n' "$SIGNATURE_NAME" "$RELEASE_BASE_URL" "$SIGNATURE_NAME" "$MANIFEST_PUBLIC_KEY_ID"
	if [ "$HARDWARE_VALIDATION" = VERIFIED ]; then
		printf 'HARDWARE_VALIDATION=VERIFIED\nPRODUCTION_GATE_SHA256=%s\nHARDWARE_EVIDENCE_ID=%s\nSERIAL_EVIDENCE_ID=%s\nTESTED_FIRMWARE_SHA256=%s\n' \
			"$PRODUCTION_GATE_SHA256" "$HARDWARE_EVIDENCE_ID" "$SERIAL_EVIDENCE_ID" "$TESTED_FIRMWARE_SHA256"
	fi
} > "$OUTPUT_WORK/RELEASE-MANIFEST"
"$USIGN_BIN" -S -m "$OUTPUT_WORK/RELEASE-MANIFEST" -s "$SIGNING_KEY" -x "$OUTPUT_WORK/$SIGNATURE_NAME"
"$USIGN_BIN" -q -V -p "$MANIFEST_PUBLIC_KEY" -m "$OUTPUT_WORK/RELEASE-MANIFEST" -x "$OUTPUT_WORK/$SIGNATURE_NAME"
if [ "$KEY_TRANSITION" -eq 1 ]; then
	"$USIGN_BIN" -S -m "$OUTPUT_WORK/RELEASE-MANIFEST" -s "$CURRENT_SIGNING_KEY" -x "$OUTPUT_WORK/RELEASE-MANIFEST.next.sig"
	"$USIGN_BIN" -q -V -p "$CURRENT_PUBLIC_KEY" -m "$OUTPUT_WORK/RELEASE-MANIFEST" -x "$OUTPUT_WORK/RELEASE-MANIFEST.next.sig"
fi

{
	printf 'version=%s\nchannel=%s\nprofile=xiaomi_ax9000_darkyun\nboard=xiaomi,ax9000-darkyun\n' "$VERSION" "$CHANNEL"
	printf 'partition_variant=darkyun-large-ubi-v1\nmibib_sha256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11\n'
	printf 'appsbl_sha256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007\n'
	printf 'openwrt_release=25.12.5\nopenwrt_commit=f0a60eee2fe051741c643ea6118718aae1ef17fb\nsource_commit=%s\n' "$SOURCE_COMMIT"
	printf 'device_patch_sha256=%s\nbuild_system=full-openwrt-buildroot\n' "$(metadata_value device_patch_sha256)"
	printf 'manifest_usign_key_id=%s\nembedded_usign_key_id=%s\n' "$MANIFEST_PUBLIC_KEY_ID" "$EMBEDDED_PUBLIC_KEY_ID"
	if [ "$KEY_TRANSITION" -eq 1 ]; then printf 'key_rotation=PREVIOUS_PRIMARY_CURRENT_COSIGN_EMBED_CURRENT\n'; else printf 'key_rotation=NONE\n'; fi
	printf 'custom_components=overlay-not-apk\nhardware_validation=%s\n' "$HARDWARE_VALIDATION"
	printf 'production_gate_sha256=%s\nhardware_evidence_id=%s\nserial_evidence_id=%s\ntested_firmware_sha256=%s\n' \
		"$PRODUCTION_GATE_SHA256" "$HARDWARE_EVIDENCE_ID" "$SERIAL_EVIDENCE_ID" "$TESTED_FIRMWARE_SHA256"
} > "$OUTPUT_WORK/BUILD-METADATA"

(
	cd "$OUTPUT_WORK"
	for artifact in *; do
		[ -f "$artifact" ] || continue
		[ "$artifact" = SHA256SUMS ] && continue
		sha256sum "$artifact"
	done
) > "$OUTPUT_WORK/SHA256SUMS"
(cd "$OUTPUT_WORK" && sha256sum -c SHA256SUMS)
mv "$OUTPUT_WORK" "$OUTPUT"
printf 'SIGNED_OUTPUT=%s\nIMAGE=%s\nSHA256=%s\nMANIFEST_USIGN_KEY_ID=%s\nEMBEDDED_USIGN_KEY_ID=%s\n' \
	"$OUTPUT" "$OUTPUT/$IMAGE_NAME" "$IMAGE_SHA" "$MANIFEST_PUBLIC_KEY_ID" "$EMBEDDED_PUBLIC_KEY_ID"
