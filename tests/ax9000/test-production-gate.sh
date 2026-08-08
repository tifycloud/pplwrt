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
BOARD=xiaomi,ax9000
HARDWARE_VARIANT=CN-label-observed
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
echo 'stable production evidence gate rejects template and accepts complete schema: ok'
