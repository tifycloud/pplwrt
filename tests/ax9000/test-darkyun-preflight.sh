#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-darkyun-preflight.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

mkdir -p "$TMP/device/proc" "$TMP/device/dev" "$TMP/device/sbin" "$TMP/device/lib/upgrade" \
	"$TMP/device/sys/class/ubi/ubi0" \
	"$TMP/device/sys/class/ubi/ubi0_0" "$TMP/device/sys/class/ubi/ubi0_1" "$TMP/device/sys/class/ubi/ubi0_2"
cat > "$TMP/device/proc/mtd" <<'EOF'
dev:    size   erasesize  name
mtd1: 00100000 00020000 "0:mibib"
mtd15: 00100000 00020000 "0:appsbl"
mtd16: 00100000 00020000 "0:appsbl_1"
mtd21: 0e800000 00020000 "rootfs"
mtd22: 00080000 00020000 "cfg_bak"
EOF
printf 'console=ttyMSM0,115200n8 ubi.mtd=rootfs root=/dev/ubiblock0_1 rootwait\n' > "$TMP/device/proc/cmdline"
printf '21\n' > "$TMP/device/sys/class/ubi/ubi0/mtd_num"
printf 'kernel\n' > "$TMP/device/sys/class/ubi/ubi0_0/name"
printf 'rootfs\n' > "$TMP/device/sys/class/ubi/ubi0_1/name"
printf 'rootfs_data\n' > "$TMP/device/sys/class/ubi/ubi0_2/name"
dd if=/dev/zero of="$TMP/device/dev/mtd1" bs=262144 count=1 2>/dev/null
dd if=/dev/zero of="$TMP/device/dev/mtd15" bs=653422 count=1 2>/dev/null
cp "$TMP/device/dev/mtd15" "$TMP/device/dev/mtd16"
printf 'fixture sysupgrade\n' > "$TMP/device/sbin/sysupgrade"
printf 'fixture platform upgrade\n' > "$TMP/device/lib/upgrade/platform.sh"
printf 'fixture nand upgrade\n' > "$TMP/device/lib/upgrade/nand.sh"
MIBIB_SHA=$(sha256sum "$TMP/device/dev/mtd1" | awk '{print $1}')
APPSBL_SHA=$(sha256sum "$TMP/device/dev/mtd15" | awk '{print $1}')
SYSUPGRADE_SHA=$(sha256sum "$TMP/device/sbin/sysupgrade" | awk '{print $1}')
PLATFORM_SHA=$(sha256sum "$TMP/device/lib/upgrade/platform.sh" | awk '{print $1}')
NAND_SHA=$(sha256sum "$TMP/device/lib/upgrade/nand.sh" | awk '{print $1}')
cat > "$TMP/spec.json" <<EOF
{
  "partition_variant": "darkyun-large-ubi-v1",
  "rootfs": {"offset_hex":"0x01180000","size_hex":"0x0e800000","erase_size_hex":"0x00020000"},
  "cfg_bak": {"offset_hex":"0x0f980000","size_hex":"0x00080000"},
  "mibib": {"read_length":262144,"sha256":"$MIBIB_SHA"},
  "appsbl": {"read_length":653422,"sha256":"$APPSBL_SHA"},
  "migration_stack": {
    "sysupgrade_sha256":"$SYSUPGRADE_SHA",
    "platform_sha256":"$PLATFORM_SHA",
    "nand_sha256":"$NAND_SHA"
  }
}
EOF

COMPANYWRT_DEVICE_ROOT="$TMP/device" \
COMPANYWRT_PREFLIGHT_TEST_MODE=1 \
	"$ROOT/scripts/ax9000-darkyun-preflight.sh" --test-mode --spec "$TMP/spec.json" --output "$TMP/evidence.env" > "$TMP/pass.out"
grep -qx 'RESULT=PASS' "$TMP/evidence.env"
grep -qx 'PARTITION_VARIANT=darkyun-large-ubi-v1' "$TMP/evidence.env"
grep -qx "MIBIB_SHA256=$MIBIB_SHA" "$TMP/evidence.env"
grep -qx "APPSBL_PRIMARY_SHA256=$APPSBL_SHA" "$TMP/evidence.env"
grep -qx "APPSBL_SECONDARY_SHA256=$APPSBL_SHA" "$TMP/evidence.env"
grep -qx "SYSUPGRADE_SHA256=$SYSUPGRADE_SHA" "$TMP/evidence.env"
grep -qx "PLATFORM_UPGRADE_SHA256=$PLATFORM_SHA" "$TMP/evidence.env"
grep -qx "NAND_UPGRADE_SHA256=$NAND_SHA" "$TMP/evidence.env"
grep -q 'No flash command was executed' "$TMP/pass.out"

printf X | dd of="$TMP/device/dev/mtd15" bs=1 seek=0 conv=notrunc 2>/dev/null
if COMPANYWRT_DEVICE_ROOT="$TMP/device" COMPANYWRT_PREFLIGHT_TEST_MODE=1 \
	"$ROOT/scripts/ax9000-darkyun-preflight.sh" --test-mode --spec "$TMP/spec.json" --output "$TMP/bad.env" > "$TMP/bad.out" 2>&1; then
	echo 'tampered APPSBL unexpectedly passed' >&2
	exit 1
fi

cp "$TMP/device/dev/mtd16" "$TMP/device/dev/mtd15"
printf 'tampered upgrade logic\n' > "$TMP/device/lib/upgrade/platform.sh"
if COMPANYWRT_DEVICE_ROOT="$TMP/device" COMPANYWRT_PREFLIGHT_TEST_MODE=1 \
	"$ROOT/scripts/ax9000-darkyun-preflight.sh" --test-mode --spec "$TMP/spec.json" --output "$TMP/bad-upgrade.env" > "$TMP/bad-upgrade.out" 2>&1; then
	echo 'tampered platform upgrade script unexpectedly passed' >&2
	exit 1
fi
printf 'fixture platform upgrade\n' > "$TMP/device/lib/upgrade/platform.sh"
sed 's/mtd21: 0e800000/mtd21: 0b680000/' "$TMP/device/proc/mtd" > "$TMP/device/proc/mtd.bad"
mv "$TMP/device/proc/mtd.bad" "$TMP/device/proc/mtd"
if COMPANYWRT_DEVICE_ROOT="$TMP/device" COMPANYWRT_PREFLIGHT_TEST_MODE=1 \
	"$ROOT/scripts/ax9000-darkyun-preflight.sh" --test-mode --spec "$TMP/spec.json" --output "$TMP/bad-layout.env" > "$TMP/bad-layout.out" 2>&1; then
	echo 'wrong rootfs size unexpectedly passed' >&2
	exit 1
fi

echo 'darkyun read-only migration preflight: ok'
