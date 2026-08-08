#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-gate-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
if "$ROOT/scripts/verify-production-gate.sh" "$ROOT/production-gates/TEMPLATE.env" 25.12.5-company.2 >"$TMP/template.out" 2>"$TMP/template.err"; then
	echo 'uncompleted production template unexpectedly passed' >&2
	exit 1
fi
grep -Eq 'APPROVED_FOR_STABLE|VERSION mismatch' "$TMP/template.err"
cat > "$TMP/evidence.env" <<'EOF'
APPROVED_FOR_STABLE=YES
VERSION=25.12.5-company.2
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11
APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007
HARDWARE_VARIANT=CN-label-observed
HARDWARE_EVIDENCE_ID=hw-record-fixture-001
SERIAL_EVIDENCE_ID=serial-record-redacted-001
SECURE_BOOT_STATE=observed-and-official-recovery-tested
BOOT_SLOT=slot-a-active-slot-b-recovery
MTD_LAYOUT=redacted-layout-reviewed
MTD_EVIDENCE_SHA256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
TEST_LOG_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
FIRMWARE_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
RESCUE=PASS
POWER_LOSS=PASS
HE80=PASS
DUAL_WAN=PASS
IPV6=PASS
VLAN=PASS
WIREGUARD=PASS
PBR=PASS
OPENCLASH=PASS
OTA=PASS
HTTPS=PASS
WAN_FIREWALL=PASS
APPROVER=fixture-reviewer
APPROVED_AT=2026-08-08T00:00:00Z
EOF
"$ROOT/scripts/verify-production-gate.sh" "$TMP/evidence.env" 25.12.5-company.2 | grep -q 'accepted'
cp "$TMP/evidence.env" "$TMP/unknown.env"
printf 'RAW_SERIAL=must-not-be-accepted\n' >> "$TMP/unknown.env"
if "$ROOT/scripts/verify-production-gate.sh" "$TMP/unknown.env" 25.12.5-company.2 >"$TMP/unknown.out" 2>"$TMP/unknown.err"; then
	echo 'unknown/raw serial evidence field unexpectedly passed' >&2
	exit 1
fi
grep -q 'unknown production evidence key' "$TMP/unknown.err"
echo 'stable production evidence gate rejects template and accepts complete schema: ok'
