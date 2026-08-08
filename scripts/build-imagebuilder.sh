#!/bin/sh
set -eu

ROOT=$(cd -P -- "$(dirname "$0")/.." && pwd)
PROFILE_FILE="$ROOT/devices/ax9000/profile.json"
PROFILE="xiaomi_ax9000"
CHANNEL="stable"
BUILD_ROOT="$ROOT/.build"
OUTPUT="$ROOT/artifacts/stable"
FORCE_DOWNLOAD=0

usage() {
  cat <<'EOF'
Usage: scripts/build-imagebuilder.sh [--profile xiaomi_ax9000]
  --channel stable|beta --build-root DIR --output DIR --force-download

The official ImageBuilder contains Linux x86_64 host tools. Apple Silicon
must use scripts/build-in-container.sh or GitHub Actions.
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --profile) PROFILE=${2:-}; shift 2 ;;
    --channel) CHANNEL=${2:-}; shift 2 ;;
    --build-root) BUILD_ROOT=${2:-}; shift 2 ;;
    --output) OUTPUT=${2:-}; shift 2 ;;
    --force-download) FORCE_DOWNLOAD=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ "$PROFILE" = xiaomi_ax9000 ] || { echo "unsupported profile: $PROFILE" >&2; exit 2; }
case "$CHANNEL" in stable|beta) : ;; *) echo "channel must be stable or beta" >&2; exit 2 ;; esac

json_value() {
  key=$1
  if command -v jq >/dev/null 2>&1; then
    jq -r "$key" "$PROFILE_FILE"
  else
    python3 - "$key" "$PROFILE_FILE" <<'PY'
import json,sys
key,path=sys.argv[1:]
v=json.load(open(path))
for part in key.lstrip('.').split('.'):
    v=v[int(part)] if isinstance(v,list) else v[part]
print(v)
PY
  fi
}

RELEASE=$(json_value '.release')
IB_NAME=$(json_value '.imagebuilder.filename')
IB_URL=$(json_value '.imagebuilder.url')
IB_SHA=$(json_value '.imagebuilder.sha256')
[ "$(json_value '.profile')" = "$PROFILE" ] || { echo "profile metadata mismatch" >&2; exit 1; }
case "$IB_URL" in https://downloads.openwrt.org/releases/$RELEASE/targets/qualcommax/ipq807x/*) : ;; *) echo "refusing unpinned URL" >&2; exit 1 ;; esac

mkdir -p "$BUILD_ROOT" "$OUTPUT"
ARCHIVE="$BUILD_ROOT/$IB_NAME"
if [ "$FORCE_DOWNLOAD" -eq 1 ] || [ ! -f "$ARCHIVE" ]; then
  command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
  curl -fL --retry 3 --retry-delay 2 "$IB_URL" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$IB_SHA" "$ARCHIVE" | sha256sum -c -
IB_DIR="$BUILD_ROOT/${IB_NAME%.tar.zst}"
if [ ! -f "$IB_DIR/Makefile" ]; then tar --zstd -xf "$ARCHIVE" -C "$BUILD_ROOT"; fi
[ -f "$IB_DIR/Makefile" ] || { echo "ImageBuilder extraction failed" >&2; exit 1; }

case "$(uname -s):$(uname -m)" in
  Linux:x86_64|Linux:amd64) ;;
  *) echo "ImageBuilder requires Linux x86_64; use build-in-container.sh or CI." >&2; exit 3 ;;
esac

OVERLAY=$(mktemp -d "$BUILD_ROOT/overlay.XXXXXX")
cleanup() { rm -rf "$OVERLAY"; }
trap cleanup EXIT INT TERM
cp -R "$ROOT/configs/overlay/." "$OVERLAY/"
mkdir -p "$OVERLAY/etc/companywrt" "$OVERLAY/usr/share/company"
cp "$ROOT/VERSION" "$OVERLAY/etc/companywrt/VERSION"
printf 'PROFILE=%s\nRELEASE=%s\nCHANNEL=%s\n' "$PROFILE" "$RELEASE" "$CHANNEL" > "$OVERLAY/etc/companywrt/build.conf"
cp "$ROOT/scripts/company-network.sh" "$OVERLAY/usr/share/company/company-network"
cp "$ROOT/scripts/ota-check.sh" "$OVERLAY/usr/share/company/ota-check"
cp "$ROOT/scripts/ota-apply.sh" "$OVERLAY/usr/share/company/ota-apply"
chmod 0755 "$OVERLAY/usr/share/company/"*

for package in luci-theme-company luci-app-company; do
  src="$ROOT/packages/$package/root"
  [ -d "$src" ] || { echo "missing package root: $src" >&2; exit 1; }
  cp -R "$src/." "$OVERLAY/"
done

PACKAGES=$(awk 'NF && $1 !~ /^#/ {printf "%s ", $1}' "$ROOT/configs/ax9000/packages.txt")
# A failed host-side probe can leave an empty generated profile cache. Always
# regenerate it inside the Linux build environment before resolving PROFILE.
rm -f "$IB_DIR/.profiles.mk"
make -C "$IB_DIR" manifest PROFILE="$PROFILE" PACKAGES="$PACKAGES" > "$OUTPUT/manifest"
make -C "$IB_DIR" image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$OVERLAY" BIN_DIR="$OUTPUT" EXTRA_IMAGE_NAME="companywrt-$CHANNEL"
IMAGE=$(find "$OUTPUT" -maxdepth 1 -type f -name "*xiaomi_ax9000*squashfs-sysupgrade.bin" -print | sort | tail -1)
[ -n "$IMAGE" ] || { echo "sysupgrade image was not produced" >&2; exit 1; }
IMAGE_NAME=$(basename "$IMAGE")
IMAGE_SHA=$(sha256sum "$IMAGE" | awk '{print $1}')
{
  printf 'VERSION=%s\n' "$(cat "$ROOT/VERSION")"
  printf 'RELEASE=%s\nPROFILE=%s\nCHANNEL=%s\n' "$RELEASE" "$PROFILE" "$CHANNEL"
  printf 'IMAGE=%s\nSHA256=%s\n' "$IMAGE_NAME" "$IMAGE_SHA"
} > "$OUTPUT/RELEASE-MANIFEST"
cp "$ROOT/VERSION" "$OUTPUT/VERSION"
(
  cd "$OUTPUT"
  for artifact in *.bin *.ubi; do
    [ -f "$artifact" ] || continue
    sha256sum "$artifact"
  done
) > "$OUTPUT/SHA256SUMS"
printf 'Built %s (%s)\n' "$IMAGE" "$IMAGE_SHA"
