#!/bin/sh
# Read-only fingerprint gate for the one-time migration from Darkyun/KWRT to
# the CompanyWrt xiaomi_ax9000_darkyun image. It never calls sysupgrade,
# fw_setenv, ubiformat, UCI, or any MTD write command.
set -eu

PARTITION_VARIANT=darkyun-large-ubi-v1
EXPECTED_MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11
EXPECTED_APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007
MIBIB_READ_LENGTH=262144
APPSBL_READ_LENGTH=653422
EXPECTED_ROOTFS_SIZE=0e800000
EXPECTED_ERASE_SIZE=00020000
EXPECTED_CFG_BAK_SIZE=00080000
EXPECTED_SYSUPGRADE_SHA256=043e8dbb000658421c303db62c6be5196f211740a1646bb988fce79fbc722f34
EXPECTED_PLATFORM_SHA256=af77cea58f86403363a13164c37926c0c1c3a451448688ce25629117f4d7d406
EXPECTED_NAND_SHA256=150eb40ac1ae56ffe1d4fcb512a8e9c8a67e5d76c3bc56fb176832aeeda4e7c5
OUTPUT=/tmp/companywrt-darkyun-preflight.env
TEST_MODE=0
TEST_SPEC=""

usage() {
	cat <<'EOF'
Usage: ax9000-darkyun-preflight.sh [--output /tmp/FILE]

Checks the exact MIBIB and both APPSBL prefixes, the current KWRT sysupgrade
stack, MTD labels/sizes, kernel boot arguments, attached UBI MTD number and the
kernel/rootfs/rootfs_data volumes. It writes a redacted evidence file and never
changes router state.

--test-mode and --spec are reserved for isolated automated fixtures.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--output) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; OUTPUT=$2; shift 2 ;;
		--test-mode) TEST_MODE=1; shift ;;
		--spec) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; TEST_SPEC=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

DEVICE_ROOT=${COMPANYWRT_DEVICE_ROOT:-}
if [ "$TEST_MODE" -eq 1 ]; then
	[ "${COMPANYWRT_PREFLIGHT_TEST_MODE:-}" = 1 ] || { echo '--test-mode requires COMPANYWRT_PREFLIGHT_TEST_MODE=1' >&2; exit 1; }
	case "$DEVICE_ROOT" in /*) ;; *) echo '--test-mode requires an absolute COMPANYWRT_DEVICE_ROOT' >&2; exit 1 ;; esac
	[ -d "$DEVICE_ROOT" ] && [ ! -L "$DEVICE_ROOT" ] || { echo 'test device root must be a real directory' >&2; exit 1; }
	tmp_real=$(realpath "${TMPDIR:-/tmp}")
	device_real=$(realpath "$DEVICE_ROOT")
	case "$device_real" in "$tmp_real"/*) ;; *) echo 'test device root must be below the temporary directory' >&2; exit 1 ;; esac
	[ -s "$TEST_SPEC" ] || { echo '--test-mode requires --spec' >&2; exit 1; }
	spec_real=$(realpath "$TEST_SPEC")
	case "$spec_real" in "$tmp_real"/*) ;; *) echo 'test spec must be below the temporary directory' >&2; exit 1 ;; esac
	json_get() {
		path=$1
		if command -v jq >/dev/null 2>&1; then
			jq -er "$path" "$TEST_SPEC"
		elif command -v python3 >/dev/null 2>&1; then
			python3 - "$path" "$TEST_SPEC" <<'PY'
import json, sys
path, filename = sys.argv[1:]
value = json.load(open(filename, encoding="utf-8"))
for part in path.lstrip(".").split("."):
    value = value[part]
print(value)
PY
		else
			echo 'test fixture parsing requires jq or python3' >&2
			exit 1
		fi
	}
	PARTITION_VARIANT=$(json_get '.partition_variant')
	EXPECTED_MIBIB_SHA256=$(json_get '.mibib.sha256')
	EXPECTED_APPSBL_SHA256=$(json_get '.appsbl.sha256')
	MIBIB_READ_LENGTH=$(json_get '.mibib.read_length')
	APPSBL_READ_LENGTH=$(json_get '.appsbl.read_length')
	EXPECTED_ROOTFS_SIZE=$(json_get '.rootfs.size_hex' | sed 's/^0x//')
	EXPECTED_ERASE_SIZE=$(json_get '.rootfs.erase_size_hex' | sed 's/^0x//')
	EXPECTED_CFG_BAK_SIZE=$(json_get '.cfg_bak.size_hex' | sed 's/^0x//')
	EXPECTED_SYSUPGRADE_SHA256=$(json_get '.migration_stack.sysupgrade_sha256')
	EXPECTED_PLATFORM_SHA256=$(json_get '.migration_stack.platform_sha256')
	EXPECTED_NAND_SHA256=$(json_get '.migration_stack.nand_sha256')
else
	[ -z "$TEST_SPEC" ] || { echo '--spec is forbidden outside test mode' >&2; exit 1; }
	[ -z "$DEVICE_ROOT" ] || { echo 'COMPANYWRT_DEVICE_ROOT is test-only' >&2; exit 1; }
	[ "$(id -u)" -eq 0 ] || { echo 'run as root on the AX9000' >&2; exit 1; }
	case "$OUTPUT" in /tmp/*) ;; *) echo 'production evidence output must be below /tmp' >&2; exit 1 ;; esac
fi

MTD_FILE="$DEVICE_ROOT/proc/mtd"
CMDLINE_FILE="$DEVICE_ROOT/proc/cmdline"
[ -r "$MTD_FILE" ] || { echo "cannot read $MTD_FILE" >&2; exit 1; }
[ -r "$CMDLINE_FILE" ] || { echo "cannot read $CMDLINE_FILE" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo 'sha256sum is required' >&2; exit 1; }
command -v dd >/dev/null 2>&1 || { echo 'dd is required' >&2; exit 1; }

file_digest() {
	path=$1
	description=$2
	[ -r "$path" ] || { echo "cannot read $description: $path" >&2; exit 1; }
	sha256sum "$path" | awk '{print $1}'
}

SYSUPGRADE_ACTUAL=$(file_digest "$DEVICE_ROOT/sbin/sysupgrade" sysupgrade)
PLATFORM_ACTUAL=$(file_digest "$DEVICE_ROOT/lib/upgrade/platform.sh" 'platform upgrade script')
NAND_ACTUAL=$(file_digest "$DEVICE_ROOT/lib/upgrade/nand.sh" 'NAND upgrade script')
[ "$SYSUPGRADE_ACTUAL" = "$EXPECTED_SYSUPGRADE_SHA256" ] || { echo 'current sysupgrade fingerprint mismatch' >&2; exit 1; }
[ "$PLATFORM_ACTUAL" = "$EXPECTED_PLATFORM_SHA256" ] || { echo 'current platform upgrade script fingerprint mismatch' >&2; exit 1; }
[ "$NAND_ACTUAL" = "$EXPECTED_NAND_SHA256" ] || { echo 'current NAND upgrade script fingerprint mismatch' >&2; exit 1; }

mtd_field() {
	label=$1
	field=$2
	awk -v wanted="\"$label\"" -v field="$field" '$4 == wanted { print $field; count++ } END { if (count != 1) exit 1 }' "$MTD_FILE"
}

mtd_number() {
	label=$1
	entry=$(mtd_field "$label" 1) || return 1
	entry=${entry%mtd:}
	entry=${entry#mtd}
	entry=${entry%:}
	printf '%s\n' "$entry"
}

require_mtd() {
	label=$1
	expected_size=$2
	actual_size=$(mtd_field "$label" 2) || { echo "required MTD label is missing or duplicated: $label" >&2; exit 1; }
	actual_erase=$(mtd_field "$label" 3) || exit 1
	[ "$actual_size" = "$expected_size" ] || { echo "$label size mismatch: expected $expected_size, got $actual_size" >&2; exit 1; }
	[ "$actual_erase" = "$EXPECTED_ERASE_SIZE" ] || { echo "$label erase size mismatch: expected $EXPECTED_ERASE_SIZE, got $actual_erase" >&2; exit 1; }
}

require_mtd '0:mibib' 00100000
require_mtd '0:appsbl' 00100000
require_mtd '0:appsbl_1' 00100000
require_mtd rootfs "$EXPECTED_ROOTFS_SIZE"
require_mtd cfg_bak "$EXPECTED_CFG_BAK_SIZE"
if grep -Eq '"ubi_kernel"' "$MTD_FILE"; then
	echo 'split-layout ubi_kernel exists; this is not the Darkyun single-UBI target' >&2
	exit 1
fi

hash_prefix() {
	device=$1
	length=$2
	[ -r "$device" ] || { echo "cannot read MTD device: $device" >&2; exit 1; }
	actual_bytes=$(wc -c < "$device" | tr -d '[:space:]')
	[ "$actual_bytes" -ge "$length" ] 2>/dev/null || { echo "MTD fixture/device is shorter than required prefix: $device" >&2; exit 1; }
	dd if="$device" bs="$length" count=1 2>/dev/null | sha256sum | awk '{print $1}'
}

MIBIB_MTD=$(mtd_number '0:mibib')
APPSBL_MTD=$(mtd_number '0:appsbl')
APPSBL_1_MTD=$(mtd_number '0:appsbl_1')
ROOTFS_MTD=$(mtd_number rootfs)
MIBIB_ACTUAL=$(hash_prefix "$DEVICE_ROOT/dev/mtd$MIBIB_MTD" "$MIBIB_READ_LENGTH")
APPSBL_ACTUAL=$(hash_prefix "$DEVICE_ROOT/dev/mtd$APPSBL_MTD" "$APPSBL_READ_LENGTH")
APPSBL_1_ACTUAL=$(hash_prefix "$DEVICE_ROOT/dev/mtd$APPSBL_1_MTD" "$APPSBL_READ_LENGTH")
[ "$MIBIB_ACTUAL" = "$EXPECTED_MIBIB_SHA256" ] || { echo 'MIBIB fingerprint mismatch' >&2; exit 1; }
[ "$APPSBL_ACTUAL" = "$EXPECTED_APPSBL_SHA256" ] || { echo 'primary APPSBL fingerprint mismatch' >&2; exit 1; }
[ "$APPSBL_1_ACTUAL" = "$EXPECTED_APPSBL_SHA256" ] || { echo 'secondary APPSBL fingerprint mismatch' >&2; exit 1; }

CMDLINE=$(cat "$CMDLINE_FILE")
printf '%s\n' "$CMDLINE" | grep -Eq '(^|[[:space:]])ubi\.mtd=rootfs([[:space:]]|$)' || { echo 'kernel command line does not attach ubi.mtd=rootfs' >&2; exit 1; }
printf '%s\n' "$CMDLINE" | grep -Eq '(^|[[:space:]])root=/dev/ubiblock0_1([[:space:]]|$)' || { echo 'kernel command line does not boot rootfs volume 1' >&2; exit 1; }

UBI_MTD_FILE=""
for candidate in "$DEVICE_ROOT"/sys/class/ubi/ubi[0-9]*/mtd_num; do
	[ -r "$candidate" ] || continue
	if [ "$(cat "$candidate")" = "$ROOTFS_MTD" ]; then
		[ -z "$UBI_MTD_FILE" ] || { echo 'multiple UBI devices are attached to rootfs MTD' >&2; exit 1; }
		UBI_MTD_FILE=$candidate
	fi
done
[ -n "$UBI_MTD_FILE" ] || { echo 'rootfs MTD is not attached as UBI' >&2; exit 1; }
UBI_DIR=${UBI_MTD_FILE%/mtd_num}
UBI_NAME=${UBI_DIR##*/}
VOLUME_NAMES=""
for name_file in "$DEVICE_ROOT/sys/class/ubi/$UBI_NAME"_*/name; do
	[ -r "$name_file" ] || continue
	VOLUME_NAMES="$VOLUME_NAMES$(cat "$name_file")\n"
done
ACTUAL_VOLUMES=$(printf '%b' "$VOLUME_NAMES" | sed '/^$/d' | LC_ALL=C sort)
EXPECTED_VOLUMES=$(printf 'kernel\nrootfs\nrootfs_data\n' | LC_ALL=C sort)
[ "$ACTUAL_VOLUMES" = "$EXPECTED_VOLUMES" ] || { echo "unexpected UBI volume set: $ACTUAL_VOLUMES" >&2; exit 1; }

case "$OUTPUT" in *[![:print:]]*|*"'"*) echo 'unsafe evidence output path' >&2; exit 1 ;; esac
if [ -e "$OUTPUT" ] || [ -L "$OUTPUT" ]; then
	echo "refusing to overwrite evidence output: $OUTPUT" >&2
	exit 1
fi
umask 077
{
	printf 'FORMAT=companywrt-darkyun-preflight-v1\n'
	printf 'RESULT=PASS\n'
	printf 'PARTITION_VARIANT=%s\n' "$PARTITION_VARIANT"
	printf 'ROOTFS_MTD=mtd%s\nROOTFS_SIZE_HEX=%s\nERASE_SIZE_HEX=%s\n' "$ROOTFS_MTD" "$EXPECTED_ROOTFS_SIZE" "$EXPECTED_ERASE_SIZE"
	printf 'UBI_VOLUMES=kernel,rootfs,rootfs_data\n'
	printf 'MIBIB_SHA256=%s\n' "$MIBIB_ACTUAL"
	printf 'APPSBL_PRIMARY_SHA256=%s\n' "$APPSBL_ACTUAL"
	printf 'APPSBL_SECONDARY_SHA256=%s\n' "$APPSBL_1_ACTUAL"
	printf 'SYSUPGRADE_SHA256=%s\n' "$SYSUPGRADE_ACTUAL"
	printf 'PLATFORM_UPGRADE_SHA256=%s\n' "$PLATFORM_ACTUAL"
	printf 'NAND_UPGRADE_SHA256=%s\n' "$NAND_ACTUAL"
	printf 'BOOT_ROOT=/dev/ubiblock0_1\n'
} > "$OUTPUT"
chmod 0600 "$OUTPUT"

printf 'PASS: this router matches the verified Darkyun single-UBI fingerprint.\n'
printf 'Evidence: %s\n' "$OUTPUT"
printf 'No flash command was executed. Candidate firmware must still pass signed bundle, embedded-DTB and sysupgrade test gates.\n'
