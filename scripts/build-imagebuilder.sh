#!/bin/sh
set -eu

CALLER_DIR=$(pwd -P)
ROOT=$(cd -P -- "$(dirname "$0")/.." && pwd)
PROFILE_FILE="$ROOT/devices/ax9000/profile.json"
PROFILE="xiaomi_ax9000"
CHANNEL=""
BUILD_ROOT="$ROOT/.build"
OUTPUT=""
FORCE_DOWNLOAD=0
PRINT_OUTPUT=0
SIGNING_KEY=${USIGN_SECRET_KEY_FILE:-}
CURRENT_SIGNING_KEY=${USIGN_CURRENT_SECRET_KEY_FILE:-}
SOURCE_COMMIT=${COMPANYWRT_SOURCE_COMMIT:-}
RELEASE_BASE_URL=""
PRODUCTION_GATE=""
VERSION=$(sed -n '1p' "$ROOT/VERSION")
HARDWARE_VALIDATION=NOT_PERFORMED_RC_ONLY
PRODUCTION_GATE_SHA256=NONE
HARDWARE_EVIDENCE_ID=NONE
SERIAL_EVIDENCE_ID=NONE
TESTED_FIRMWARE_SHA256=NONE

usage() {
	cat <<'EOF'
Usage: scripts/build-imagebuilder.sh [options]
  --profile xiaomi_ax9000
  --channel stable|rc|beta
  --build-root DIR
  --output DIR
  --signing-key FILE        manifest usign private key outside the repository
  --current-signing-key FILE
                            current key used for a declared rotation transition
  --production-gate FILE    exact stable hardware evidence file
  --source-commit 40HEX
  --release-base-url HTTPS_URL
  --force-download
  --print-output            print resolved versioned output and exit

Default output is artifacts/<channel>/<VERSION>/. Every full build requires a
usign private key matching the manifest trust key. A declared rotation build
also requires the current private key while embedding only the current public
key. Private keys are never copied to FILES or artifacts. Stable builds require
the exact production-gates/<VERSION>.env file. Official ImageBuilder host tools
require Linux x86_64; Apple Silicon must use the container wrapper or CI.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2 ;;
		--channel) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; CHANNEL=$2; shift 2 ;;
		--build-root) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; BUILD_ROOT=$2; shift 2 ;;
		--output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; OUTPUT=$2; shift 2 ;;
		--signing-key) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; SIGNING_KEY=$2; shift 2 ;;
		--current-signing-key) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; CURRENT_SIGNING_KEY=$2; shift 2 ;;
		--production-gate) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PRODUCTION_GATE=$2; shift 2 ;;
		--source-commit) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; SOURCE_COMMIT=$2; shift 2 ;;
		--release-base-url) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; RELEASE_BASE_URL=$2; shift 2 ;;
		--force-download) FORCE_DOWNLOAD=1; shift ;;
		--print-output) PRINT_OUTPUT=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
	esac
done

printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-company\.[0-9]+(-(rc|beta)[1-9][0-9]*)?$' || { echo "invalid VERSION: $VERSION" >&2; exit 1; }
if [ -z "$CHANNEL" ]; then
	case "$VERSION" in *-rc[1-9]*) CHANNEL=rc ;; *-beta[1-9]*) CHANNEL=beta ;; *) CHANNEL=stable ;; esac
fi
case "$CHANNEL" in stable|rc|beta) ;; *) echo "channel must be stable, rc or beta" >&2; exit 2 ;; esac
case "$CHANNEL" in
	rc) printf '%s\n' "$VERSION" | grep -Eq -- '-rc[1-9][0-9]*$' || { echo 'rc builds require an -rcN VERSION' >&2; exit 1; } ;;
	beta) printf '%s\n' "$VERSION" | grep -Eq -- '-beta[1-9][0-9]*$' || { echo 'beta builds require a -betaN VERSION' >&2; exit 1; } ;;
	stable) printf '%s\n' "$VERSION" | grep -Eq -- '-(rc|beta)[1-9][0-9]*$' && { echo 'stable builds cannot use prerelease VERSION values' >&2; exit 1; } ;;
esac

gate_value() {
	key=$1
	awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' "$PRODUCTION_GATE"
}

if [ "$CHANNEL" = stable ]; then
	[ -n "$PRODUCTION_GATE" ] || { echo 'stable builds require --production-gate production-gates/<VERSION>.env' >&2; exit 1; }
	case "$PRODUCTION_GATE" in /*) ;; *) PRODUCTION_GATE="$CALLER_DIR/$PRODUCTION_GATE" ;; esac
	[ -f "$PRODUCTION_GATE" ] || { echo "production gate not found: $PRODUCTION_GATE" >&2; exit 1; }
	[ "$(realpath "$PRODUCTION_GATE")" = "$(realpath "$ROOT/production-gates/$VERSION.env")" ] || {
		echo "stable builds require the exact repository evidence production-gates/$VERSION.env" >&2
		exit 1
	}
	"$ROOT/scripts/verify-production-gate.sh" "$PRODUCTION_GATE" "$VERSION"
	HARDWARE_VALIDATION=VERIFIED
	PRODUCTION_GATE_SHA256=$(sha256sum "$PRODUCTION_GATE" | awk '{print $1}')
	HARDWARE_EVIDENCE_ID=$(gate_value HARDWARE_EVIDENCE_ID)
	SERIAL_EVIDENCE_ID=$(gate_value SERIAL_EVIDENCE_ID)
	TESTED_FIRMWARE_SHA256=$(gate_value FIRMWARE_SHA256)
elif [ -n "$PRODUCTION_GATE" ]; then
	echo '--production-gate is valid only for stable builds' >&2
	exit 1
fi

[ "$PROFILE" = xiaomi_ax9000 ] || { echo "unsupported profile: $PROFILE" >&2; exit 2; }
if [ -z "$OUTPUT" ]; then
	OUTPUT="$ROOT/artifacts/$CHANNEL/$VERSION"
fi
case "$BUILD_ROOT" in /*) ;; *) BUILD_ROOT="$CALLER_DIR/$BUILD_ROOT" ;; esac
case "$OUTPUT" in /*) ;; *) OUTPUT="$CALLER_DIR/$OUTPUT" ;; esac
if [ "$PRINT_OUTPUT" -eq 1 ]; then
	printf '%s\n' "$OUTPUT"
	exit 0
fi

if [ -z "$SOURCE_COMMIT" ] && command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
	SOURCE_COMMIT=$(git -C "$ROOT" rev-parse HEAD)
fi
printf '%s\n' "$SOURCE_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || { echo '--source-commit (or COMPANYWRT_SOURCE_COMMIT) must be 40 lowercase hex' >&2; exit 1; }
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse HEAD >/dev/null 2>&1; then
	[ "$(git -C "$ROOT" rev-parse HEAD)" = "$SOURCE_COMMIT" ] || { echo 'source commit does not match repository HEAD' >&2; exit 1; }
	[ -z "$(git -C "$ROOT" status --porcelain --untracked-files=all)" ] || { echo 'refusing to bind a dirty worktree to a release source commit' >&2; exit 1; }
elif [ "${COMPANYWRT_SOURCE_VERIFIED:-}" != 1 ]; then
	echo 'source provenance cannot be verified outside git; use the clean-worktree container wrapper' >&2
	exit 1
fi
if [ -z "$RELEASE_BASE_URL" ]; then
	RELEASE_BASE_URL="https://github.com/tifycloud/pplwrt/releases/download/v$VERSION"
fi
case "$RELEASE_BASE_URL" in https://*) ;; *) echo 'release base URL must use HTTPS' >&2; exit 1 ;; esac
case "$RELEASE_BASE_URL" in *[!A-Za-z0-9._~:/%-]*) echo 'release base URL contains unsupported characters' >&2; exit 1 ;; esac

ROTATION_FILE="$ROOT/keys/ROTATION.env"
[ -s "$ROTATION_FILE" ] || { echo 'usign rotation declaration is missing' >&2; exit 1; }
rotation_value() {
	key=$1
	awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' "$ROTATION_FILE"
}
[ "$(rotation_value FORMAT)" = companywrt-usign-rotation-v1 ] || { echo 'unsupported usign rotation declaration' >&2; exit 1; }
TRANSITION_VERSION=$(rotation_value TRANSITION_VERSION)
PREVIOUS_PUBLIC_KEY_REL=$(rotation_value PREVIOUS_PUBLIC_KEY)
CURRENT_PUBLIC_KEY_REL=$(rotation_value CURRENT_PUBLIC_KEY)
[ "$PREVIOUS_PUBLIC_KEY_REL" = keys/companywrt-release-previous.pub ] || { echo 'unexpected previous public key path in ROTATION.env' >&2; exit 1; }
[ "$CURRENT_PUBLIC_KEY_REL" = keys/companywrt-release.pub ] || { echo 'unexpected current public key path in ROTATION.env' >&2; exit 1; }
printf '%s\n' "$TRANSITION_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-company\.[0-9]+-(rc|beta)[1-9][0-9]*$' || { echo 'invalid transition VERSION in ROTATION.env' >&2; exit 1; }
PREVIOUS_PUBLIC_KEY="$ROOT/$PREVIOUS_PUBLIC_KEY_REL"
EMBEDDED_PUBLIC_KEY="$ROOT/$CURRENT_PUBLIC_KEY_REL"
DECLARED_PREVIOUS_KEY_ID=$(rotation_value PREVIOUS_KEY_ID)
DECLARED_CURRENT_KEY_ID=$(rotation_value CURRENT_KEY_ID)
printf '%s\n' "$DECLARED_PREVIOUS_KEY_ID" | grep -Eq '^[0-9a-f]{16}$' || { echo 'previous rotation key ID must be 16 lowercase hex' >&2; exit 1; }
printf '%s\n' "$DECLARED_CURRENT_KEY_ID" | grep -Eq '^[0-9a-f]{16}$' || { echo 'current rotation key ID must be 16 lowercase hex' >&2; exit 1; }
if [ ! -s "$PREVIOUS_PUBLIC_KEY" ] || [ ! -s "$EMBEDDED_PUBLIC_KEY" ]; then
	echo 'declared usign public keys are missing' >&2
	exit 1
fi

KEY_TRANSITION=0
MANIFEST_PUBLIC_KEY=$EMBEDDED_PUBLIC_KEY
if [ "$VERSION" = "$TRANSITION_VERSION" ]; then
	KEY_TRANSITION=1
	MANIFEST_PUBLIC_KEY=$PREVIOUS_PUBLIC_KEY
fi

root_real=$(realpath "$ROOT")
validate_secret_path() {
	secret_path=$1
	description=$2
	[ -s "$secret_path" ] || { echo "a non-empty $description is required outside the repository" >&2; exit 1; }
	secret_real=$(realpath "$secret_path")
	case "$secret_real" in "$root_real"/*) echo "refusing $description stored inside the repository" >&2; exit 1 ;; esac
}
validate_secret_path "$SIGNING_KEY" 'manifest usign private key (--signing-key or USIGN_SECRET_KEY_FILE)'
if [ "$KEY_TRANSITION" -eq 1 ]; then
	validate_secret_path "$CURRENT_SIGNING_KEY" 'current rotation usign private key (--current-signing-key or USIGN_CURRENT_SECRET_KEY_FILE)'
elif [ -n "$CURRENT_SIGNING_KEY" ]; then
	echo 'current rotation signing key was supplied outside the declared transition version' >&2
	exit 1
fi
awk -F'|' -v expected="$VERSION" '
	/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
	{ version=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", version); if (version != expected) exit 1 }
' "$ROOT/CUSTOM-COMPONENTS.manifest" || { echo 'CUSTOM-COMPONENTS.manifest version mismatch' >&2; exit 1; }

json_value() {
	key=$1
	if command -v jq >/dev/null 2>&1; then
		jq -r "$key" "$PROFILE_FILE"
	else
		python3 - "$key" "$PROFILE_FILE" <<'PY'
import json,sys
key,path=sys.argv[1:]
value=json.load(open(path, encoding="utf-8"))
for part in key.lstrip('.').split('.'):
    value=value[int(part)] if isinstance(value,list) else value[part]
print(value)
PY
	fi
}

RELEASE=$(json_value '.release')
IB_NAME=$(json_value '.imagebuilder.filename')
IB_URL=$(json_value '.imagebuilder.url')
IB_SHA=$(json_value '.imagebuilder.sha256')
[ "$(json_value '.profile')" = "$PROFILE" ] || { echo 'profile metadata mismatch' >&2; exit 1; }
case "$IB_URL" in https://downloads.openwrt.org/releases/$RELEASE/targets/qualcommax/ipq807x/*) ;; *) echo 'refusing unpinned ImageBuilder URL' >&2; exit 1 ;; esac

mkdir -p "$BUILD_ROOT"
ARCHIVE="$BUILD_ROOT/$IB_NAME"
if [ "$FORCE_DOWNLOAD" -eq 1 ] || [ ! -f "$ARCHIVE" ]; then
	command -v curl >/dev/null 2>&1 || { echo 'curl is required' >&2; exit 1; }
	curl --fail --location --retry 3 --retry-delay 2 --proto '=https' --proto-redir '=https' "$IB_URL" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$IB_SHA" "$ARCHIVE" | sha256sum -c -
IB_DIR="$BUILD_ROOT/${IB_NAME%.tar.zst}"
if [ ! -f "$IB_DIR/Makefile" ]; then tar --zstd -xf "$ARCHIVE" -C "$BUILD_ROOT"; fi
[ -f "$IB_DIR/Makefile" ] || { echo 'ImageBuilder extraction failed' >&2; exit 1; }

case "$(uname -s):$(uname -m)" in Linux:x86_64|Linux:amd64) ;; *) echo 'ImageBuilder requires Linux x86_64; use build-in-container.sh or CI.' >&2; exit 3 ;; esac
USIGN_BIN="$IB_DIR/staging_dir/host/bin/usign"
[ -x "$USIGN_BIN" ] || { echo 'pinned ImageBuilder host usign is missing' >&2; exit 1; }
MANIFEST_PUBLIC_KEY_ID=$("$USIGN_BIN" -F -p "$MANIFEST_PUBLIC_KEY")
EMBEDDED_PUBLIC_KEY_ID=$("$USIGN_BIN" -F -p "$EMBEDDED_PUBLIC_KEY")
SECRET_KEY_ID=$("$USIGN_BIN" -F -s "$SIGNING_KEY")
[ "$MANIFEST_PUBLIC_KEY_ID" = "$SECRET_KEY_ID" ] || { echo 'manifest usign private key does not match its committed public key' >&2; exit 1; }
[ "$EMBEDDED_PUBLIC_KEY_ID" = "$DECLARED_CURRENT_KEY_ID" ] || { echo 'current public key ID does not match ROTATION.env' >&2; exit 1; }
[ "$("$USIGN_BIN" -F -p "$PREVIOUS_PUBLIC_KEY")" = "$DECLARED_PREVIOUS_KEY_ID" ] || { echo 'previous public key ID does not match ROTATION.env' >&2; exit 1; }
if [ "$KEY_TRANSITION" -eq 1 ]; then
	CURRENT_SECRET_KEY_ID=$("$USIGN_BIN" -F -s "$CURRENT_SIGNING_KEY")
	[ "$CURRENT_SECRET_KEY_ID" = "$EMBEDDED_PUBLIC_KEY_ID" ] || { echo 'current rotation private key does not match the embedded public key' >&2; exit 1; }
	[ "$MANIFEST_PUBLIC_KEY_ID" = "$DECLARED_PREVIOUS_KEY_ID" ] || { echo 'transition manifest must be signed by the declared previous key' >&2; exit 1; }
else
	[ "$MANIFEST_PUBLIC_KEY_ID" = "$EMBEDDED_PUBLIC_KEY_ID" ] || { echo 'non-transition manifest must use the embedded current public key' >&2; exit 1; }
fi

[ ! -e "$OUTPUT" ] || { echo "refusing existing output directory: $OUTPUT" >&2; exit 1; }
OUTPUT_PARENT=$(dirname "$OUTPUT")
mkdir -p "$OUTPUT_PARENT"
OUTPUT_WORK=$(mktemp -d "$OUTPUT_PARENT/.companywrt-$VERSION.XXXXXX")
OVERLAY=$(mktemp -d "$BUILD_ROOT/overlay.XXXXXX")
cleanup() {
	rm -rf "$OVERLAY"
	[ ! -d "$OUTPUT_WORK" ] || rm -rf "$OUTPUT_WORK"
}
trap cleanup EXIT INT TERM

cp -R "$ROOT/configs/overlay/." "$OVERLAY/"
for package in luci-theme-company luci-app-company; do
	src="$ROOT/packages/$package/root"
	[ -d "$src" ] || { echo "missing overlay component root: $src" >&2; exit 1; }
	cp -R "$src/." "$OVERLAY/"
done
# Finder metadata is ignored by git but may exist in a developer checkout.
# Never let host-only files become part of the firmware overlay.
find "$OVERLAY" -type f -name .DS_Store -delete
[ -z "$(find "$OVERLAY" -name .DS_Store -print -quit)" ] || { echo 'host metadata leaked into firmware overlay' >&2; exit 1; }
if find "$OVERLAY" -type f \( -name '*.key' -o -name '*.sec' -o -name '*.secret' -o -name '*.pem' -o -name '.env' \) ! -path '*/etc/companywrt/keys/release.pub' -print -quit | grep -q .; then
	echo 'refusing secret-like material in the firmware overlay' >&2
	exit 1
fi
mkdir -p "$OVERLAY/etc/companywrt/keys" "$OVERLAY/usr/share/company"
cp "$ROOT/VERSION" "$OVERLAY/etc/companywrt/VERSION"
# Keep the image byte-for-byte testable before a production evidence file is
# committed. Exact source provenance remains signed in RELEASE-MANIFEST and
# BUILD-METADATA; embedding the commit would make an evidence file containing
# the firmware hash self-referential.
printf 'PROFILE=%s\nRELEASE=%s\nCHANNEL=%s\n' "$PROFILE" "$RELEASE" "$CHANNEL" > "$OVERLAY/etc/companywrt/build.conf"
cp "$EMBEDDED_PUBLIC_KEY" "$OVERLAY/etc/companywrt/keys/release.pub"
cp "$ROOT/LICENSE" "$OVERLAY/usr/share/company/LICENSE"
cp "$ROOT/NOTICE" "$OVERLAY/usr/share/company/NOTICE"
cp "$ROOT/CUSTOM-COMPONENTS.manifest" "$OVERLAY/usr/share/company/CUSTOM-COMPONENTS.manifest"
cp "$ROOT/scripts/company-network.sh" "$OVERLAY/usr/share/company/company-network"
cp "$ROOT/scripts/ota-common.sh" "$OVERLAY/usr/share/company/ota-common.sh"
cp "$ROOT/scripts/ota-check.sh" "$OVERLAY/usr/share/company/ota-check"
cp "$ROOT/scripts/ota-apply.sh" "$OVERLAY/usr/share/company/ota-apply"
cp "$ROOT/scripts/enrollment-preflight.sh" "$OVERLAY/usr/share/company/enrollment-preflight"
chmod 0755 "$OVERLAY/usr/share/company/company-network" "$OVERLAY/usr/share/company/ota-check" \
	"$OVERLAY/usr/share/company/ota-apply" "$OVERLAY/usr/share/company/enrollment-preflight"
chmod 0644 "$OVERLAY/usr/share/company/ota-common.sh" "$OVERLAY/etc/companywrt/keys/release.pub"

PACKAGES=$(awk 'NF && $1 !~ /^#/ {printf "%s ", $1}' "$ROOT/configs/ax9000/packages.txt")
rm -f "$IB_DIR/.profiles.mk"
attempt=1
while ! make -C "$IB_DIR" manifest PROFILE="$PROFILE" PACKAGES="$PACKAGES" > "$OUTPUT_WORK/manifest.raw"; do
	[ "$attempt" -lt 3 ] || { echo 'ImageBuilder manifest failed after 3 attempts' >&2; exit 1; }
	printf 'ImageBuilder manifest attempt %s failed; retrying with the same verified cache\n' "$attempt" >&2
	sleep "$attempt"
	attempt=$((attempt + 1))
done
awk '/^[A-Za-z0-9][A-Za-z0-9+_.@-]* - [^[:space:]]+$/ { print }' "$OUTPUT_WORK/manifest.raw" | LC_ALL=C sort -u > "$OUTPUT_WORK/PACKAGE-MANIFEST"
[ "$(wc -l < "$OUTPUT_WORK/PACKAGE-MANIFEST" | tr -d '[:space:]')" -eq 251 ] || { echo 'resolved package manifest must contain exactly 251 unique package/version entries' >&2; exit 1; }
[ "$(awk -F' - ' '{print $1}' "$OUTPUT_WORK/PACKAGE-MANIFEST" | LC_ALL=C sort -u | wc -l | tr -d '[:space:]')" -eq 251 ] || { echo 'resolved package manifest contains duplicate package names' >&2; exit 1; }

EXTRA_IMAGE_NAME="companywrt-$VERSION-$CHANNEL"
attempt=1
while ! make -C "$IB_DIR" image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$OVERLAY" BIN_DIR="$OUTPUT_WORK" EXTRA_IMAGE_NAME="$EXTRA_IMAGE_NAME"; do
	[ "$attempt" -lt 3 ] || { echo 'ImageBuilder image failed after 3 attempts' >&2; exit 1; }
	printf 'ImageBuilder image attempt %s failed; retrying with the same verified cache\n' "$attempt" >&2
	sleep "$attempt"
	attempt=$((attempt + 1))
done
rm -f "$OUTPUT_WORK/sha256sums" "$OUTPUT_WORK/SHA256SUMS" "$OUTPUT_WORK/manifest.raw"
[ -s "$OUTPUT_WORK/profiles.json" ] || { echo 'ImageBuilder profiles.json was not produced' >&2; exit 1; }
IMAGE_NAME=$(python3 - "$OUTPUT_WORK/profiles.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
profile = document.get("profiles", {}).get("xiaomi_ax9000")
if not isinstance(profile, dict) or profile.get("supported_devices") != ["xiaomi,ax9000"]:
    raise SystemExit("profiles.json does not describe only the expected AX9000 board")
matches = [
    image.get("name")
    for image in profile.get("images", [])
    if image.get("type") == "sysupgrade" and image.get("filesystem") == "squashfs"
]
if len(matches) != 1 or not isinstance(matches[0], str) or "/" in matches[0]:
    raise SystemExit("profiles.json must identify exactly one squashfs sysupgrade image")
print(matches[0])
PY
)
IMAGE="$OUTPUT_WORK/$IMAGE_NAME"
[ -f "$IMAGE" ] || { echo "profiles.json sysupgrade image was not produced: $IMAGE_NAME" >&2; exit 1; }
IMAGE_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
IMAGE_SIZE=$(wc -c < "$IMAGE" | tr -d '[:space:]')
if [ "$HARDWARE_VALIDATION" = VERIFIED ]; then
	[ "$IMAGE_SHA" = "$TESTED_FIRMWARE_SHA256" ] || {
		echo 'stable blocked: built firmware does not match the exact hardware-tested digest' >&2
		exit 1
	}
fi

cp "$ROOT/VERSION" "$OUTPUT_WORK/VERSION"
cp "$ROOT/LICENSE" "$OUTPUT_WORK/LICENSE"
cp "$ROOT/NOTICE" "$OUTPUT_WORK/NOTICE"
cp "$ROOT/CUSTOM-COMPONENTS.manifest" "$OUTPUT_WORK/CUSTOM-COMPONENTS.manifest"
cp "$ROOT/docs/CHANGELOG.md" "$OUTPUT_WORK/RELEASE-NOTES.md"
SBOM_COUNT=0
for sbom in "$OUTPUT_WORK"/*.bom.cdx.json; do
	[ -f "$sbom" ] || continue
	python3 "$ROOT/scripts/augment-sbom.py" \
		--sbom "$sbom" \
		--components "$ROOT/CUSTOM-COMPONENTS.manifest" \
		--package-manifest "$OUTPUT_WORK/PACKAGE-MANIFEST" \
		--expected-package-count 251
	SBOM_COUNT=$((SBOM_COUNT + 1))
done
[ "$SBOM_COUNT" -ge 1 ] || { echo 'ImageBuilder did not produce a CycloneDX SBOM' >&2; exit 1; }

"$ROOT/scripts/inspect-firmware.sh" \
	--image "$IMAGE" \
	--package-manifest "$OUTPUT_WORK/PACKAGE-MANIFEST" \
	--report "$OUTPUT_WORK/FIRMWARE-CONTENT-REPORT.txt" \
	--embedded-key-id "$EMBEDDED_PUBLIC_KEY_ID" \
	--hardware-validation "$HARDWARE_VALIDATION" \
	--production-gate-sha256 "$PRODUCTION_GATE_SHA256" \
	--hardware-evidence-id "$HARDWARE_EVIDENCE_ID" \
	--serial-evidence-id "$SERIAL_EVIDENCE_ID" \
	--tested-firmware-sha256 "$TESTED_FIRMWARE_SHA256"

SIGNATURE_NAME='RELEASE-MANIFEST.sig'
{
	if [ "$HARDWARE_VALIDATION" = VERIFIED ]; then
		printf 'FORMAT=companywrt-release-v2\n'
	else
		printf 'FORMAT=companywrt-release-v1\n'
	fi
	printf 'VERSION=%s\n' "$VERSION"
	printf 'OPENWRT_RELEASE=%s\n' "$RELEASE"
	printf 'PROFILE=%s\n' "$PROFILE"
	printf 'BOARD=xiaomi,ax9000\n'
	printf 'CHANNEL=%s\n' "$CHANNEL"
	printf 'TAG=v%s\n' "$VERSION"
	printf 'SOURCE_COMMIT=%s\n' "$SOURCE_COMMIT"
	printf 'IMAGE=%s\n' "$IMAGE_NAME"
	printf 'SHA256=%s\n' "$IMAGE_SHA"
	printf 'SIZE=%s\n' "$IMAGE_SIZE"
	printf 'URL=%s/%s\n' "$RELEASE_BASE_URL" "$IMAGE_NAME"
	printf 'SIGNATURE=%s\n' "$SIGNATURE_NAME"
	printf 'SIGNATURE_URL=%s/%s\n' "$RELEASE_BASE_URL" "$SIGNATURE_NAME"
	printf 'USIGN_KEY_ID=%s\n' "$MANIFEST_PUBLIC_KEY_ID"
	if [ "$HARDWARE_VALIDATION" = VERIFIED ]; then
		printf 'HARDWARE_VALIDATION=%s\n' "$HARDWARE_VALIDATION"
		printf 'PRODUCTION_GATE_SHA256=%s\n' "$PRODUCTION_GATE_SHA256"
		printf 'HARDWARE_EVIDENCE_ID=%s\n' "$HARDWARE_EVIDENCE_ID"
		printf 'SERIAL_EVIDENCE_ID=%s\n' "$SERIAL_EVIDENCE_ID"
		printf 'TESTED_FIRMWARE_SHA256=%s\n' "$TESTED_FIRMWARE_SHA256"
	fi
} > "$OUTPUT_WORK/RELEASE-MANIFEST"
"$USIGN_BIN" -S -m "$OUTPUT_WORK/RELEASE-MANIFEST" -s "$SIGNING_KEY" -x "$OUTPUT_WORK/$SIGNATURE_NAME"
"$USIGN_BIN" -q -V -p "$MANIFEST_PUBLIC_KEY" -m "$OUTPUT_WORK/RELEASE-MANIFEST" -x "$OUTPUT_WORK/$SIGNATURE_NAME"
if [ "$KEY_TRANSITION" -eq 1 ]; then
	NEXT_SIGNATURE_NAME='RELEASE-MANIFEST.next.sig'
	"$USIGN_BIN" -S -m "$OUTPUT_WORK/RELEASE-MANIFEST" -s "$CURRENT_SIGNING_KEY" -x "$OUTPUT_WORK/$NEXT_SIGNATURE_NAME"
	"$USIGN_BIN" -q -V -p "$EMBEDDED_PUBLIC_KEY" -m "$OUTPUT_WORK/RELEASE-MANIFEST" -x "$OUTPUT_WORK/$NEXT_SIGNATURE_NAME"
fi

{
	printf 'version=%s\nchannel=%s\nprofile=%s\nboard=xiaomi,ax9000\n' "$VERSION" "$CHANNEL" "$PROFILE"
	printf 'openwrt_release=%s\nsource_commit=%s\n' "$RELEASE" "$SOURCE_COMMIT"
	printf 'imagebuilder_url=%s\nimagebuilder_sha256=%s\n' "$IB_URL" "$IB_SHA"
	printf 'manifest_usign_key_id=%s\nembedded_usign_key_id=%s\n' "$MANIFEST_PUBLIC_KEY_ID" "$EMBEDDED_PUBLIC_KEY_ID"
	if [ "$KEY_TRANSITION" -eq 1 ]; then
		printf 'key_rotation=PREVIOUS_PRIMARY_CURRENT_COSIGN_EMBED_CURRENT\n'
	else
		printf 'key_rotation=NONE\n'
	fi
	printf 'custom_components=overlay-not-apk\n'
	printf 'hardware_validation=%s\n' "$HARDWARE_VALIDATION"
	printf 'production_gate_sha256=%s\n' "$PRODUCTION_GATE_SHA256"
	printf 'hardware_evidence_id=%s\n' "$HARDWARE_EVIDENCE_ID"
	printf 'serial_evidence_id=%s\n' "$SERIAL_EVIDENCE_ID"
	printf 'tested_firmware_sha256=%s\n' "$TESTED_FIRMWARE_SHA256"
} > "$OUTPUT_WORK/BUILD-METADATA"

(
	cd "$OUTPUT_WORK"
	for artifact in *; do
		[ -f "$artifact" ] || continue
		[ "$artifact" = SHA256SUMS ] && continue
		sha256sum "$artifact"
	done
) > "$OUTPUT_WORK/SHA256SUMS"
(
	cd "$OUTPUT_WORK"
	sha256sum -c SHA256SUMS
)

mv "$OUTPUT_WORK" "$OUTPUT"
printf 'OUTPUT=%s\n' "$OUTPUT"
printf 'IMAGE=%s\n' "$OUTPUT/$IMAGE_NAME"
printf 'SHA256=%s\nSIZE=%s\nMANIFEST_USIGN_KEY_ID=%s\nEMBEDDED_USIGN_KEY_ID=%s\n' "$IMAGE_SHA" "$IMAGE_SIZE" "$MANIFEST_PUBLIC_KEY_ID" "$EMBEDDED_PUBLIC_KEY_ID"
