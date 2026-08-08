#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-sign-bundle.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
INPUT="$TMP/unsigned"
OUTPUT="$TMP/signed"
mkdir -p "$INPUT"
VERSION=$(sed -n '1p' "$ROOT/VERSION")
SOURCE_COMMIT=$(git -C "$ROOT" rev-parse HEAD)

printf 'unsigned firmware fixture\n' > "$INPUT/openwrt-25.12.5-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin"
IMAGE_SHA=$(sha256sum "$INPUT/openwrt-25.12.5-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin" | awk '{print $1}')
{
	i=1
	while [ "$i" -le 251 ]; do
		printf 'fixture-package-%03d - 1.0\n' "$i"
		i=$((i + 1))
	done
} > "$INPUT/PACKAGE-MANIFEST"
cat > "$INPUT/FIRMWARE-CONTENT-REPORT.txt" <<EOF
image_sha256=$IMAGE_SHA
kernel_dtb_layout=PASS
partition_variant=darkyun-large-ubi-v1
hardware_validation=NOT_PERFORMED_RC_ONLY
EOF
cat > "$INPUT/BUILD-METADATA" <<EOF
version=$VERSION
channel=rc
profile=xiaomi_ax9000_darkyun
board=xiaomi,ax9000-darkyun
partition_variant=darkyun-large-ubi-v1
openwrt_release=25.12.5
openwrt_commit=f0a60eee2fe051741c643ea6118718aae1ef17fb
source_commit=$SOURCE_COMMIT
device_patch_sha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
build_system=full-openwrt-buildroot
release_signing=NOT_PERFORMED_COMPILE_ONLY
hardware_validation=NOT_PERFORMED_RC_ONLY
EOF
printf 'UNSIGNED DEVELOPMENT PREFLIGHT ONLY\n' > "$INPUT/COMPILE-ONLY-NOT-A-RELEASE.txt"

mkdir -p "$TMP/host-usign/bin"
cat > "$TMP/host-usign/bin/usign" <<'EOF'
#!/bin/sh
set -eu
mode=$1
case "$mode" in
	-F)
		kind=$2; path=$3
		case "$kind:$path" in
			-p:*previous.pub|-s:*previous.key) echo 679439846de7ada5 ;;
			-p:*release.pub|-s:*current.key) echo 444eb53ba66e6d45 ;;
			*) exit 1 ;;
		esac
		;;
	-S)
		output=''
		while [ "$#" -gt 0 ]; do
			case "$1" in -x) output=$2; shift 2 ;; *) shift ;; esac
		done
		[ -n "$output" ]
		printf 'mock usign signature\n' > "$output"
		;;
	-q)
		[ "$2" = -V ] || exit 1
		;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$TMP/host-usign/bin/usign"
tar --zstd -cf "$INPUT/BUILD-HOST-USIGN.tar.zst" -C "$TMP/host-usign" bin
(
	cd "$INPUT"
	for artifact in *; do
		[ "$artifact" = SHA256SUMS ] && continue
		sha256sum "$artifact"
	done
) > "$INPUT/SHA256SUMS"
printf 'mock previous key\n' > "$TMP/previous.key"
printf 'mock current key\n' > "$TMP/current.key"

"$ROOT/scripts/sign-release-bundle.sh" --input "$INPUT" --output "$OUTPUT" --channel rc \
	--signing-key "$TMP/previous.key" --current-signing-key "$TMP/current.key" > "$TMP/sign.out"

[ -s "$OUTPUT/RELEASE-MANIFEST" ]
[ -s "$OUTPUT/RELEASE-MANIFEST.sig" ]
[ -s "$OUTPUT/RELEASE-MANIFEST.next.sig" ]
[ ! -e "$OUTPUT/BUILD-HOST-USIGN.tar.zst" ]
[ ! -e "$OUTPUT/COMPILE-ONLY-NOT-A-RELEASE.txt" ]
grep -qx 'FORMAT=companywrt-darkyun-release-v1' "$OUTPUT/RELEASE-MANIFEST"
grep -qx 'USIGN_KEY_ID=679439846de7ada5' "$OUTPUT/RELEASE-MANIFEST"
grep -qx 'key_rotation=PREVIOUS_PRIMARY_CURRENT_COSIGN_EMBED_CURRENT' "$OUTPUT/BUILD-METADATA"
(cd "$OUTPUT" && sha256sum -c SHA256SUMS >/dev/null)

printf 'tamper\n' >> "$INPUT/PACKAGE-MANIFEST"
if "$ROOT/scripts/sign-release-bundle.sh" --input "$INPUT" --output "$TMP/tampered" --channel rc \
	--signing-key "$TMP/previous.key" --current-signing-key "$TMP/current.key" > "$TMP/tampered.out" 2>&1; then
	echo 'tampered unsigned bundle unexpectedly reached signing' >&2
	exit 1
fi

echo 'no-secret compile bundle isolation and release signing conversion: ok'
