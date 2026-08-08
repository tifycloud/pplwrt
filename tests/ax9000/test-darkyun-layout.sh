#!/bin/sh
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
SPEC="$ROOT/devices/ax9000/darkyun-large-ubi.json"
PATCH_FILE="$ROOT/devices/ax9000/patches/0001-qualcommax-add-ax9000-darkyun-large-ubi.patch"

command -v jq >/dev/null 2>&1 || { echo 'jq is required' >&2; exit 1; }
[ -s "$SPEC" ] || { echo 'darkyun device specification is missing' >&2; exit 1; }
[ -s "$PATCH_FILE" ] || { echo 'darkyun OpenWrt patch is missing' >&2; exit 1; }

[ "$(jq -r '.openwrt.release' "$SPEC")" = 25.12.5 ]
[ "$(jq -r '.openwrt.commit' "$SPEC")" = f0a60eee2fe051741c643ea6118718aae1ef17fb ]
[ "$(jq -r '.profile' "$SPEC")" = xiaomi_ax9000_darkyun ]
[ "$(jq -r '.board' "$SPEC")" = xiaomi,ax9000-darkyun ]
[ "$(jq -r '.partition_variant' "$SPEC")" = darkyun-large-ubi-v1 ]
[ "$(jq -r '.rootfs.offset_hex' "$SPEC")" = 0x01180000 ]
[ "$(jq -r '.rootfs.size_hex' "$SPEC")" = 0x0e800000 ]
[ "$(jq -r '.rootfs.size_bytes' "$SPEC")" -eq 243269632 ]
[ "$(jq -r '.cfg_bak.offset_hex' "$SPEC")" = 0x0f980000 ]
[ "$(jq -r '.cfg_bak.size_hex' "$SPEC")" = 0x00080000 ]
[ "$(jq -r '.mibib.sha256' "$SPEC")" = 2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11 ]
[ "$(jq -r '.appsbl.sha256' "$SPEC")" = 80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007 ]
[ "$(jq -r '.live_validation.result' "$SPEC")" = PASS ]
[ "$(jq -r '.live_validation.method' "$SPEC")" = read-only-ssh-preflight-v1 ]
[ "$(jq -r '.live_validation.rootfs_mtd' "$SPEC")" = mtd21 ]
[ "$(jq -r '.migration_stack.sysupgrade_sha256' "$SPEC")" = 043e8dbb000658421c303db62c6be5196f211740a1646bb988fce79fbc722f34 ]
[ "$(jq -r '.migration_stack.platform_sha256' "$SPEC")" = af77cea58f86403363a13164c37926c0c1c3a451448688ce25629117f4d7d406 ]
[ "$(jq -r '.migration_stack.nand_sha256' "$SPEC")" = 150eb40ac1ae56ffe1d4fcb512a8e9c8a67e5d76c3bc56fb176832aeeda4e7c5 ]

grep -Fq 'compatible = "xiaomi,ax9000-darkyun", "xiaomi,ax9000", "qcom,ipq8074"' "$PATCH_FILE"
grep -Fq 'label = "rootfs"' "$PATCH_FILE"
grep -Fq 'reg = <0x1180000 0xe800000>' "$PATCH_FILE"
grep -Fq 'label = "cfg_bak"' "$PATCH_FILE"
grep -Fq 'reg = <0xf980000 0x80000>' "$PATCH_FILE"
if grep -Fq 'SUPPORTED_DEVICES := xiaomi,ax9000-darkyun xiaomi,ax9000' "$PATCH_FILE"; then
	echo 'custom image must not broadly advertise compatibility with standard AX9000' >&2
	exit 1
fi
if sed -n '/define Device\/xiaomi_ax9000_darkyun/,/TARGET_DEVICES += xiaomi_ax9000_darkyun/p' "$PATCH_FILE" | grep -Fq "\$(call Device/UbiFit)"; then
	echo 'custom migration target must not emit an untested factory UBI image' >&2
	exit 1
fi
grep -Eq '^\+[[:space:]]+KERNEL_IN_UBI := 1$' "$PATCH_FILE"
grep -Fq 'CI_UBIPART="rootfs"' "$PATCH_FILE"
grep -Fq "nand_do_upgrade \"\$1\"" "$PATCH_FILE"

grep -Fq 'PROFILE=xiaomi_ax9000_darkyun' "$ROOT/scripts/sign-release-bundle.sh"
grep -Fq 'BOARD=xiaomi,ax9000-darkyun' "$ROOT/scripts/sign-release-bundle.sh"
grep -Fq 'PARTITION_VARIANT=darkyun-large-ubi-v1' "$ROOT/scripts/sign-release-bundle.sh"
grep -Fq 'MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11' "$ROOT/scripts/sign-release-bundle.sh"
grep -Fq 'APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007' "$ROOT/scripts/sign-release-bundle.sh"

echo 'darkyun single-UBI device contract: ok'
