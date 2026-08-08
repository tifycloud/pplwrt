#!/bin/sh
set -eu

CALLER_DIR=$(pwd -P)
ROOT=$(cd -P -- "$(dirname "$0")/.." && pwd)
PROFILE_FILE="$ROOT/devices/ax9000/darkyun-large-ubi.json"
PATCH_FILE="$ROOT/devices/ax9000/patches/0001-qualcommax-add-ax9000-darkyun-large-ubi.patch"
PROFILE="xiaomi_ax9000_darkyun"
BOARD="xiaomi,ax9000-darkyun"
CHANNEL=""
BUILD_ROOT="$ROOT/.build"
OUTPUT=""
FORCE_SOURCE=0
PRINT_OUTPUT=0
COMPILE_ONLY=0
JOBS=${COMPANYWRT_BUILD_JOBS:-2}
SOURCE_COMMIT=${COMPANYWRT_SOURCE_COMMIT:-}
PRODUCTION_GATE=""
VERSION=$(sed -n '1p' "$ROOT/VERSION")
HARDWARE_VALIDATION=NOT_PERFORMED_RC_ONLY
PRODUCTION_GATE_SHA256=NONE
HARDWARE_EVIDENCE_ID=NONE
SERIAL_EVIDENCE_ID=NONE
TESTED_FIRMWARE_SHA256=NONE
EXPECTED_PACKAGE_COUNT=252

usage() {
	cat <<'EOF'
Usage: scripts/build-buildroot.sh [options]
  --profile xiaomi_ax9000_darkyun
  --channel stable|rc|beta
  --build-root DIR
  --output DIR
  --production-gate FILE    exact stable hardware evidence file
  --source-commit 40HEX
  --jobs N                   parallel compiler jobs (default 2)
  --force-source             discard only the generated pinned source cache
  --compile-only             unsigned local preflight; never a release bundle
  --print-output            print resolved versioned output and exit

This compiler accepts only --compile-only and never accepts or reads a release
private key. The resulting unsigned bundle is signed later by
sign-release-bundle.sh in the isolated release environment. Stable builds
require the exact production-gates/<VERSION>.env file. Linux x86_64 is required;
Apple Silicon must use the container wrapper or CI.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--profile) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PROFILE=$2; shift 2 ;;
		--channel) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; CHANNEL=$2; shift 2 ;;
		--build-root) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; BUILD_ROOT=$2; shift 2 ;;
		--output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; OUTPUT=$2; shift 2 ;;
		--production-gate) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PRODUCTION_GATE=$2; shift 2 ;;
		--source-commit) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; SOURCE_COMMIT=$2; shift 2 ;;
		--jobs) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; JOBS=$2; shift 2 ;;
		--force-source) FORCE_SOURCE=1; shift ;;
		--compile-only) COMPILE_ONLY=1; shift ;;
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
[ "$COMPILE_ONLY" -eq 1 ] || { echo 'Buildroot is compile-only; pass --compile-only and sign the verified bundle separately' >&2; exit 1; }

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

[ "$PROFILE" = xiaomi_ax9000_darkyun ] || { echo "unsupported profile: $PROFILE" >&2; exit 2; }
printf '%s\n' "$JOBS" | grep -Eq '^[1-9][0-9]?$' || { echo '--jobs must be an integer from 1 to 99' >&2; exit 2; }
if [ -z "$OUTPUT" ]; then
	OUTPUT="$ROOT/artifacts/preflight/$VERSION"
fi
case "$BUILD_ROOT" in /*) ;; *) BUILD_ROOT="$CALLER_DIR/$BUILD_ROOT" ;; esac
case "$OUTPUT" in /*) ;; *) OUTPUT="$CALLER_DIR/$OUTPUT" ;; esac
if [ "$PRINT_OUTPUT" -eq 1 ]; then
	printf '%s\n' "$OUTPUT"
	exit 0
fi
[ "$(id -u)" -ne 0 ] || { echo 'refusing full Buildroot compilation as root; use the non-root container wrapper' >&2; exit 1; }

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

RELEASE=$(json_value '.openwrt.release')
OPENWRT_COMMIT=$(json_value '.openwrt.commit')
OPENWRT_TAG=$(json_value '.openwrt.tag')
OPENWRT_SOURCE_URL=$(json_value '.openwrt.source')
PARTITION_VARIANT=$(json_value '.partition_variant')
[ "$(json_value '.package_inventory.expected_count')" = "$EXPECTED_PACKAGE_COUNT" ] || { echo 'device package inventory count mismatch' >&2; exit 1; }
[ "$(json_value '.package_inventory.required_selection')" = configs/ax9000/packages.txt ] || { echo 'device required package selection path mismatch' >&2; exit 1; }
[ "$(json_value '.profile')" = "$PROFILE" ] || { echo 'profile metadata mismatch' >&2; exit 1; }
[ "$(json_value '.board')" = "$BOARD" ] || { echo 'board metadata mismatch' >&2; exit 1; }
printf '%s\n' "$OPENWRT_COMMIT" | grep -Eq '^[0-9a-f]{40}$' || { echo 'pinned OpenWrt commit is invalid' >&2; exit 1; }
case "$OPENWRT_SOURCE_URL" in https://git.openwrt.org/openwrt/openwrt.git) ;; *) echo 'refusing unapproved OpenWrt source URL' >&2; exit 1 ;; esac
[ -s "$PATCH_FILE" ] || { echo "reviewed device patch is missing: $PATCH_FILE" >&2; exit 1; }

mkdir -p "$BUILD_ROOT"
case "$(uname -s):$(uname -m)" in
	Linux:x86_64|Linux:amd64) ;;
	*) echo 'full OpenWrt Buildroot requires Linux x86_64; use build-in-container.sh or CI.' >&2; exit 3 ;;
esac

SOURCE_DIR="$BUILD_ROOT/openwrt-$RELEASE-$PROFILE"
remove_generated_source() {
	case "$SOURCE_DIR" in
		"$BUILD_ROOT"/openwrt-*) rm -rf "$SOURCE_DIR" ;;
		*) echo 'refusing unsafe generated source path' >&2; exit 1 ;;
	esac
}
if [ "$FORCE_SOURCE" -eq 1 ] && [ -e "$SOURCE_DIR" ]; then
	remove_generated_source
fi
if [ ! -d "$SOURCE_DIR/.git" ]; then
	source_attempt=1
	while ! git clone --depth=1 --branch "$OPENWRT_TAG" --no-checkout "$OPENWRT_SOURCE_URL" "$SOURCE_DIR"; do
		remove_generated_source
		[ "$source_attempt" -lt 3 ] || { echo 'OpenWrt source checkout failed after 3 attempts' >&2; exit 1; }
		printf 'OpenWrt source checkout attempt %s failed; retrying the pinned repository\n' "$source_attempt" >&2
		sleep "$source_attempt"
		source_attempt=$((source_attempt + 1))
	done
fi
source_attempt=1
while ! git -C "$SOURCE_DIR" fetch --depth=1 origin "refs/tags/$OPENWRT_TAG"; do
	[ "$source_attempt" -lt 3 ] || { echo 'OpenWrt pinned tag fetch failed after 3 attempts' >&2; exit 1; }
	printf 'OpenWrt pinned tag fetch attempt %s failed; retrying\n' "$source_attempt" >&2
	sleep "$source_attempt"
	source_attempt=$((source_attempt + 1))
done
[ "$(git -C "$SOURCE_DIR" rev-parse 'FETCH_HEAD^{commit}')" = "$OPENWRT_COMMIT" ] || { echo 'OpenWrt tag did not resolve to the pinned commit' >&2; exit 1; }

PATCH_SHA256=$(sha256sum "$PATCH_FILE" | awk '{print $1}')
PATCH_MARKER="$SOURCE_DIR/.companywrt-darkyun-patch"
if [ ! -f "$PATCH_MARKER" ]; then
	git -C "$SOURCE_DIR" switch --detach "$OPENWRT_COMMIT"
	[ -z "$(git -C "$SOURCE_DIR" status --porcelain --untracked-files=all)" ] || { echo 'new OpenWrt source checkout is unexpectedly dirty' >&2; exit 1; }
	git -C "$SOURCE_DIR" apply --check "$PATCH_FILE"
	git -C "$SOURCE_DIR" apply "$PATCH_FILE"
	printf '%s\n' "$PATCH_SHA256" > "$PATCH_MARKER"
else
	[ "$(git -C "$SOURCE_DIR" rev-parse HEAD)" = "$OPENWRT_COMMIT" ] || { echo 'cached OpenWrt source commit mismatch; rerun with --force-source' >&2; exit 1; }
	[ "$(sed -n '1p' "$PATCH_MARKER")" = "$PATCH_SHA256" ] || { echo 'cached device patch mismatch; rerun with --force-source' >&2; exit 1; }
fi
git -C "$SOURCE_DIR" diff --check

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
printf 'PROFILE=%s\nBOARD=%s\nPARTITION_VARIANT=%s\nRELEASE=%s\nCHANNEL=%s\n' \
	"$PROFILE" "$BOARD" "$PARTITION_VARIANT" "$RELEASE" "$CHANNEL" > "$OVERLAY/etc/companywrt/build.conf"
cp "$PROFILE_FILE" "$OVERLAY/etc/companywrt/device-layout.json"
cp "$EMBEDDED_PUBLIC_KEY" "$OVERLAY/etc/companywrt/keys/release.pub"
cp "$ROOT/LICENSE" "$OVERLAY/usr/share/company/LICENSE"
cp "$ROOT/NOTICE" "$OVERLAY/usr/share/company/NOTICE"
cp "$ROOT/CUSTOM-COMPONENTS.manifest" "$OVERLAY/usr/share/company/CUSTOM-COMPONENTS.manifest"
cp "$ROOT/scripts/company-network.sh" "$OVERLAY/usr/share/company/company-network"
cp "$ROOT/scripts/ota-common.sh" "$OVERLAY/usr/share/company/ota-common.sh"
cp "$ROOT/scripts/ota-check.sh" "$OVERLAY/usr/share/company/ota-check"
cp "$ROOT/scripts/ota-apply.sh" "$OVERLAY/usr/share/company/ota-apply"
cp "$ROOT/scripts/enrollment-preflight.sh" "$OVERLAY/usr/share/company/enrollment-preflight"
cp "$ROOT/scripts/ax9000-darkyun-preflight.sh" "$OVERLAY/usr/share/company/ax9000-darkyun-preflight"
chmod 0755 "$OVERLAY/usr/share/company/company-network" "$OVERLAY/usr/share/company/ota-check" \
	"$OVERLAY/usr/share/company/ota-apply" "$OVERLAY/usr/share/company/enrollment-preflight" \
	"$OVERLAY/usr/share/company/ax9000-darkyun-preflight"
chmod 0644 "$OVERLAY/usr/share/company/ota-common.sh" "$OVERLAY/etc/companywrt/keys/release.pub"

PACKAGES=$(awk 'NF && $1 !~ /^#/ {printf "%s ", $1}' "$ROOT/configs/ax9000/packages.txt")
FILES_DIR="$SOURCE_DIR/files"
case "$FILES_DIR" in "$SOURCE_DIR"/files) rm -rf "$FILES_DIR" ;; *) echo 'refusing unsafe OpenWrt files path' >&2; exit 1 ;; esac
mkdir -p "$FILES_DIR"
cp -R "$OVERLAY/." "$FILES_DIR/"

(
	cd "$SOURCE_DIR"
	./scripts/feeds update -a
	./scripts/feeds install -a
)

{
	printf 'CONFIG_TARGET_qualcommax=y\n'
	printf 'CONFIG_TARGET_qualcommax_ipq807x=y\n'
	printf 'CONFIG_TARGET_qualcommax_ipq807x_DEVICE_xiaomi_ax9000_darkyun=y\n'
	printf 'CONFIG_TARGET_ROOTFS_SQUASHFS=y\n'
	printf 'CONFIG_JSON_OVERVIEW_IMAGE_INFO=y\n'
	printf 'CONFIG_JSON_CYCLONEDX_SBOM=y\n'
	# LuCI translation packages are generated from the language selector. Merely
	# selecting their package names is discarded by defconfig when the language
	# tristate is unset.
	printf 'CONFIG_LUCI_LANG_zh_Hans=y\n'
	printf '# CONFIG_PACKAGE_dnsmasq is not set\n'
	# OpenClash only needs Ruby/YAML parsing. The feeds default enables Ruby
	# YJIT on aarch64, which adds a full Rust/LLVM host toolchain without
	# providing any required router functionality.
	printf '# CONFIG_RUBY_ENABLE_YJIT is not set\n'
	for package in $PACKAGES; do
		printf 'CONFIG_PACKAGE_%s=y\n' "$package"
	done
} > "$SOURCE_DIR/.config"

make -C "$SOURCE_DIR" defconfig
grep -qx 'CONFIG_TARGET_qualcommax_ipq807x_DEVICE_xiaomi_ax9000_darkyun=y' "$SOURCE_DIR/.config" || { echo 'custom target disappeared during defconfig' >&2; exit 1; }
grep -qx 'CONFIG_PACKAGE_dnsmasq-full=y' "$SOURCE_DIR/.config" || { echo 'dnsmasq-full was not selected' >&2; exit 1; }
grep -qx 'CONFIG_LUCI_LANG_zh_Hans=y' "$SOURCE_DIR/.config" || { echo 'Simplified Chinese LuCI language was not selected' >&2; exit 1; }
for translation in luci-i18n-base-zh-cn luci-i18n-pbr-zh-cn; do
	grep -qx "CONFIG_PACKAGE_${translation}=y" "$SOURCE_DIR/.config" || { echo "required LuCI translation was not selected: $translation" >&2; exit 1; }
done
if grep -qx 'CONFIG_PACKAGE_dnsmasq=y' "$SOURCE_DIR/.config"; then
	echo 'conflicting dnsmasq package remained selected' >&2
	exit 1
fi

TARGET_BIN="$SOURCE_DIR/bin/targets/qualcommax/ipq807x"
case "$TARGET_BIN" in "$SOURCE_DIR"/bin/targets/qualcommax/ipq807x) rm -rf "$TARGET_BIN" ;; *) echo 'refusing unsafe target output path' >&2; exit 1 ;; esac

attempt=1
while ! make -C "$SOURCE_DIR" -j "$JOBS" download; do
	[ "$attempt" -lt 3 ] || { echo 'OpenWrt source download failed after 3 attempts' >&2; exit 1; }
	printf 'OpenWrt download attempt %s failed; retrying verified sources\n' "$attempt" >&2
	sleep "$attempt"
	attempt=$((attempt + 1))
done
make -C "$SOURCE_DIR" -j "$JOBS"

USIGN_BIN="$SOURCE_DIR/staging_dir/host/bin/usign"
[ -x "$USIGN_BIN" ] || { echo 'pinned Buildroot host usign is missing' >&2; exit 1; }
EMBEDDED_PUBLIC_KEY_ID=$("$USIGN_BIN" -F -p "$EMBEDDED_PUBLIC_KEY")
[ "$EMBEDDED_PUBLIC_KEY_ID" = "$DECLARED_CURRENT_KEY_ID" ] || { echo 'current public key ID does not match ROTATION.env' >&2; exit 1; }
[ "$("$USIGN_BIN" -F -p "$PREVIOUS_PUBLIC_KEY")" = "$DECLARED_PREVIOUS_KEY_ID" ] || { echo 'previous public key ID does not match ROTATION.env' >&2; exit 1; }

[ -s "$TARGET_BIN/profiles.json" ] || { echo 'Buildroot profiles.json was not produced' >&2; exit 1; }
cp "$TARGET_BIN/profiles.json" "$OUTPUT_WORK/profiles.json"
IMAGE_NAME=$(python3 - "$OUTPUT_WORK/profiles.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
profile = document.get("profiles", {}).get("xiaomi_ax9000_darkyun")
if not isinstance(profile, dict) or profile.get("supported_devices") != ["xiaomi,ax9000-darkyun"]:
    raise SystemExit("profiles.json does not describe only the Darkyun AX9000 board")
matches = [
    image.get("name")
    for image in profile.get("images", [])
    if image.get("type") == "sysupgrade" and image.get("filesystem") == "squashfs"
]
if any(image.get("type") == "factory" for image in profile.get("images", [])):
    raise SystemExit("untested factory image output is forbidden for the Darkyun migration target")
if len(matches) != 1 or not isinstance(matches[0], str) or "/" in matches[0]:
    raise SystemExit("profiles.json must identify exactly one squashfs sysupgrade image")
print(matches[0])
PY
)
SOURCE_IMAGE="$TARGET_BIN/$IMAGE_NAME"
[ -f "$SOURCE_IMAGE" ] || { echo "profiles.json sysupgrade image was not produced: $IMAGE_NAME" >&2; exit 1; }
cp "$SOURCE_IMAGE" "$OUTPUT_WORK/$IMAGE_NAME"
IMAGE="$OUTPUT_WORK/$IMAGE_NAME"

IMAGE_PREFIX=${IMAGE_NAME%-squashfs-sysupgrade.bin}
SOURCE_PACKAGE_MANIFEST="$TARGET_BIN/$IMAGE_PREFIX.manifest"
SOURCE_SBOM="$TARGET_BIN/$IMAGE_PREFIX.bom.cdx.json"
[ -s "$SOURCE_PACKAGE_MANIFEST" ] || { echo 'Buildroot package manifest is missing' >&2; exit 1; }
[ -s "$SOURCE_SBOM" ] || { echo 'Buildroot CycloneDX SBOM is missing' >&2; exit 1; }
awk '/^[A-Za-z0-9][A-Za-z0-9+_.@-]* - [^[:space:]]+$/ { print }' "$SOURCE_PACKAGE_MANIFEST" | LC_ALL=C sort -u > "$OUTPUT_WORK/PACKAGE-MANIFEST"
[ "$(wc -l < "$OUTPUT_WORK/PACKAGE-MANIFEST" | tr -d '[:space:]')" -eq "$EXPECTED_PACKAGE_COUNT" ] || { echo "resolved package manifest must contain exactly $EXPECTED_PACKAGE_COUNT unique package/version entries" >&2; exit 1; }
[ "$(awk -F' - ' '{print $1}' "$OUTPUT_WORK/PACKAGE-MANIFEST" | LC_ALL=C sort -u | wc -l | tr -d '[:space:]')" -eq "$EXPECTED_PACKAGE_COUNT" ] || { echo 'resolved package manifest contains duplicate package names' >&2; exit 1; }
for package in $PACKAGES; do
	awk -F' - ' -v wanted="$package" '$1 == wanted { found=1 } END { exit !found }' "$OUTPUT_WORK/PACKAGE-MANIFEST" || {
		echo "selected package is missing from resolved manifest: $package" >&2
		exit 1
	}
done
cp "$SOURCE_SBOM" "$OUTPUT_WORK/$IMAGE_PREFIX.bom.cdx.json"
cp "$SOURCE_DIR/.config" "$OUTPUT_WORK/OPENWRT-CONFIG"
{
	printf 'openwrt_release=%s\nopenwrt_commit=%s\n' "$RELEASE" "$OPENWRT_COMMIT"
	printf 'device_patch_sha256=%s\npartition_variant=%s\n' "$PATCH_SHA256" "$PARTITION_VARIANT"
	for feed in packages luci routing telephony video; do
		printf 'feed_%s_commit=%s\n' "$feed" "$(git -C "$SOURCE_DIR/feeds/$feed" rev-parse HEAD)"
	done
} > "$OUTPUT_WORK/OPENWRT-SOURCE-PROVENANCE"
IMAGE_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
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
cp "$ROOT/scripts/ax9000-darkyun-first-flash.sh" "$OUTPUT_WORK/ax9000-darkyun-first-flash.sh"
cp "$ROOT/scripts/ax9000-darkyun-preflight.sh" "$OUTPUT_WORK/ax9000-darkyun-preflight.sh"
cp "$ROOT/scripts/ota-common.sh" "$OUTPUT_WORK/ota-common.sh"
cp "$ROOT/keys/companywrt-release-previous.pub" "$OUTPUT_WORK/companywrt-release-previous.pub"
cp "$ROOT/keys/companywrt-release.pub" "$OUTPUT_WORK/companywrt-release.pub"
chmod 0755 "$OUTPUT_WORK/ax9000-darkyun-first-flash.sh" "$OUTPUT_WORK/ax9000-darkyun-preflight.sh"
chmod 0644 "$OUTPUT_WORK/ota-common.sh" "$OUTPUT_WORK/companywrt-release-previous.pub" "$OUTPUT_WORK/companywrt-release.pub"
SBOM_COUNT=0
for sbom in "$OUTPUT_WORK"/*.bom.cdx.json; do
	[ -f "$sbom" ] || continue
	python3 "$ROOT/scripts/augment-sbom.py" \
		--sbom "$sbom" \
		--components "$ROOT/CUSTOM-COMPONENTS.manifest" \
		--package-manifest "$OUTPUT_WORK/PACKAGE-MANIFEST" \
		--expected-package-count "$EXPECTED_PACKAGE_COUNT"
	SBOM_COUNT=$((SBOM_COUNT + 1))
done
[ "$SBOM_COUNT" -eq 1 ] || { echo 'Buildroot must produce exactly one custom-profile CycloneDX SBOM' >&2; exit 1; }

DUMPIMAGE="$SOURCE_DIR/staging_dir/host/bin/dumpimage" \
DTC="$SOURCE_DIR/staging_dir/host/bin/dtc" \
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

tar --zstd -cf "$OUTPUT_WORK/BUILD-HOST-USIGN.tar.zst" \
	-C "$SOURCE_DIR/staging_dir/host" bin/usign bin/.usign.bin lib
{
	printf 'UNSIGNED DEVELOPMENT PREFLIGHT ONLY\n'
	printf 'This directory is not a release bundle and must not be flashed.\n'
} > "$OUTPUT_WORK/COMPILE-ONLY-NOT-A-RELEASE.txt"
{
	printf 'version=%s\nchannel=%s\nprofile=%s\nboard=%s\n' "$VERSION" "$CHANNEL" "$PROFILE" "$BOARD"
	printf 'partition_variant=%s\nopenwrt_release=%s\nopenwrt_commit=%s\n' "$PARTITION_VARIANT" "$RELEASE" "$OPENWRT_COMMIT"
	printf 'source_commit=%s\ndevice_patch_sha256=%s\nbuild_system=full-openwrt-buildroot\n' "$SOURCE_COMMIT" "$PATCH_SHA256"
	printf 'package_count=%s\n' "$EXPECTED_PACKAGE_COUNT"
	printf 'release_signing=NOT_PERFORMED_COMPILE_ONLY\nhardware_validation=%s\n' "$HARDWARE_VALIDATION"
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
(
	cd "$OUTPUT_WORK"
	sha256sum -c SHA256SUMS
)

mv "$OUTPUT_WORK" "$OUTPUT"
printf 'COMPILE_ONLY_OUTPUT=%s\nIMAGE=%s\nSHA256=%s\n' "$OUTPUT" "$OUTPUT/$IMAGE_NAME" "$IMAGE_SHA"
