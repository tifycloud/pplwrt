#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-first-flash.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
MOCK="$TMP/mock-bin"
DEVICE="$TMP/device"
mkdir -p "$MOCK" "$DEVICE/proc" "$DEVICE/dev" "$DEVICE/sbin" "$DEVICE/lib/upgrade" \
	"$DEVICE/sys/class/ubi/ubi0" \
	"$DEVICE/sys/class/ubi/ubi0_0" "$DEVICE/sys/class/ubi/ubi0_1" "$DEVICE/sys/class/ubi/ubi0_2" \
	"$DEVICE/sys/class/mtd/mtd21" "$DEVICE/sys/class/mtd/mtd22"

cat > "$DEVICE/proc/mtd" <<'EOF'
dev:    size   erasesize  name
mtd1: 00100000 00020000 "0:mibib"
mtd15: 00100000 00020000 "0:appsbl"
mtd16: 00100000 00020000 "0:appsbl_1"
mtd21: 0e800000 00020000 "rootfs"
mtd22: 00080000 00020000 "cfg_bak"
EOF
printf 'ubi.mtd=rootfs root=/dev/ubiblock0_1\n' > "$DEVICE/proc/cmdline"
printf '21\n' > "$DEVICE/sys/class/ubi/ubi0/mtd_num"
printf 'kernel\n' > "$DEVICE/sys/class/ubi/ubi0_0/name"
printf 'rootfs\n' > "$DEVICE/sys/class/ubi/ubi0_1/name"
printf 'rootfs_data\n' > "$DEVICE/sys/class/ubi/ubi0_2/name"
printf '18350080\n' > "$DEVICE/sys/class/mtd/mtd21/offset"
printf '261619712\n' > "$DEVICE/sys/class/mtd/mtd22/offset"
dd if=/dev/zero of="$DEVICE/dev/mtd1" bs=262144 count=1 2>/dev/null
dd if=/dev/zero of="$DEVICE/dev/mtd15" bs=653422 count=1 2>/dev/null
cp "$DEVICE/dev/mtd15" "$DEVICE/dev/mtd16"
printf 'fixture sysupgrade\n' > "$DEVICE/sbin/sysupgrade"
printf 'fixture platform upgrade\n' > "$DEVICE/lib/upgrade/platform.sh"
printf 'fixture nand upgrade\n' > "$DEVICE/lib/upgrade/nand.sh"
MIBIB_SHA=$(sha256sum "$DEVICE/dev/mtd1" | awk '{print $1}')
APPSBL_SHA=$(sha256sum "$DEVICE/dev/mtd15" | awk '{print $1}')
SYSUPGRADE_SHA=$(sha256sum "$DEVICE/sbin/sysupgrade" | awk '{print $1}')
PLATFORM_SHA=$(sha256sum "$DEVICE/lib/upgrade/platform.sh" | awk '{print $1}')
NAND_SHA=$(sha256sum "$DEVICE/lib/upgrade/nand.sh" | awk '{print $1}')
cat > "$TMP/spec.json" <<EOF
{"partition_variant":"darkyun-large-ubi-v1","rootfs":{"offset_hex":"0x01180000","size_hex":"0x0e800000","erase_size_hex":"0x00020000"},"cfg_bak":{"offset_hex":"0x0f980000","size_hex":"0x00080000"},"mibib":{"read_length":262144,"sha256":"$MIBIB_SHA"},"appsbl":{"read_length":653422,"sha256":"$APPSBL_SHA"},"migration_stack":{"sysupgrade_sha256":"$SYSUPGRADE_SHA","platform_sha256":"$PLATFORM_SHA","nand_sha256":"$NAND_SHA"}}
EOF

cat > "$MOCK/id" <<'EOF'
#!/bin/sh
[ "${1:-}" = -u ] && { echo 0; exit 0; }
exit 1
EOF
cat > "$MOCK/usign" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = -F ]; then echo 679439846de7ada5; exit 0; fi
[ "$1" = -q ] && shift
[ "$1" = -V ] || exit 2
shift
message=''; signature=''
while [ "$#" -gt 0 ]; do
	case "$1" in -p) shift 2 ;; -m) message=$2; shift 2 ;; -x) signature=$2; shift 2 ;; *) exit 2 ;; esac
done
[ "$(sha256sum "$message" | awk '{print $1}')" = "$(sed -n '1p' "$signature")" ]
EOF
cat > "$MOCK/ubus" <<'EOF'
#!/bin/sh
echo '{"board_name":"xiaomi,ax9000","release":{"version":"23.05.5","target":"ipq807x/generic"}}'
EOF
cat > "$MOCK/jsonfilter" <<'EOF'
#!/bin/sh
case "$2" in @.board_name) echo xiaomi,ax9000 ;; @.release.version) echo 23.05.5 ;; @.release.target) echo ipq807x/generic ;; *) exit 1 ;; esac
EOF
cat > "$MOCK/sysupgrade" <<'EOF'
#!/bin/sh
[ "$1" = -T ] && [ "$2" = -F ] && [ -f "$3" ] || exit 1
printf '%s\n' "$*" >> "$SYSUPGRADE_LOG"
EOF
chmod 0755 "$MOCK"/*

printf 'first-flash fixture\n' > "$TMP/image.bin"
IMAGE_SHA=$(sha256sum "$TMP/image.bin" | awk '{print $1}')
IMAGE_SIZE=$(wc -c < "$TMP/image.bin" | tr -d '[:space:]')
IMAGE_NAME=openwrt-25.12.5-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin
cat > "$TMP/manifest" <<EOF
FORMAT=companywrt-darkyun-release-v1
VERSION=25.12.5-company.2-rc2
OPENWRT_RELEASE=25.12.5
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11
APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007
MIGRATION_BOARD=xiaomi,ax9000
CHANNEL=rc
TAG=v25.12.5-company.2-rc2
SOURCE_COMMIT=0123456789abcdef0123456789abcdef01234567
IMAGE=$IMAGE_NAME
SHA256=$IMAGE_SHA
SIZE=$IMAGE_SIZE
URL=https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2-rc2/$IMAGE_NAME
SIGNATURE=RELEASE-MANIFEST.sig
SIGNATURE_URL=https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2-rc2/RELEASE-MANIFEST.sig
USIGN_KEY_ID=679439846de7ada5
EOF
sha256sum "$TMP/manifest" | awk '{print $1}' > "$TMP/manifest.sig"
SYSUPGRADE_LOG="$TMP/sysupgrade.log"; export SYSUPGRADE_LOG

PATH="$MOCK:$PATH" COMPANYWRT_FIRST_FLASH_TEST_MODE=1 COMPANYWRT_PREFLIGHT_TEST_MODE=1 \
COMPANYWRT_DEVICE_ROOT="$DEVICE" "$ROOT/scripts/ax9000-darkyun-first-flash.sh" --test-mode \
	--spec "$TMP/spec.json" --manifest "$TMP/manifest" --signature "$TMP/manifest.sig" \
	--image "$TMP/image.bin" --public-key "$ROOT/keys/companywrt-release-previous.pub" \
	--work-dir "$TMP/stage" --expected-version 25.12.5-company.2-rc2 \
	--confirm-version 25.12.5-company.2-rc2 --confirm-sha256 "$IMAGE_SHA" > "$TMP/out"
grep -q 'FIRST-FLASH CANDIDATE PASSED' "$TMP/out"
grep -q 'Final manual command (NOT executed): sysupgrade -n -F' "$TMP/out"
[ "$(wc -l < "$SYSUPGRADE_LOG" | tr -d '[:space:]')" -eq 1 ]
grep -q '^-T -F ' "$SYSUPGRADE_LOG"

echo 'Darkyun one-time first-flash wrapper fingerprint/signature/force-test gates: ok'
