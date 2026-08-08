#!/bin/sh
# Validate a redacted, human-approved real-hardware stable-release evidence file.
set -eu

[ "$#" -eq 2 ] || { echo 'Usage: verify-production-gate.sh FILE VERSION' >&2; exit 2; }
EVIDENCE=$1
EXPECTED_VERSION=$2
[ -s "$EVIDENCE" ] || { echo "production evidence missing: $EVIDENCE" >&2; exit 1; }

value() {
	key=$1
	awk -F= -v wanted="$key" '$1 == wanted { print substr($0, index($0, "=") + 1); exit }' "$EVIDENCE"
}

awk -F= '
	/^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
	NF < 2 || $1 !~ /^[A-Z0-9_]+$/ { print "invalid evidence line: " $0 > "/dev/stderr"; exit 1 }
	seen[$1]++ { print "duplicate evidence key: " $1 > "/dev/stderr"; exit 1 }
' "$EVIDENCE" || exit 1

[ "$(value APPROVED_FOR_STABLE)" = YES ] || { echo 'APPROVED_FOR_STABLE=YES is required' >&2; exit 1; }
[ "$(value VERSION)" = "$EXPECTED_VERSION" ] || { echo 'production evidence VERSION mismatch' >&2; exit 1; }
[ "$(value BOARD)" = xiaomi,ax9000 ] || { echo 'production evidence BOARD mismatch' >&2; exit 1; }
for key in RESCUE POWER_LOSS HE80 DUAL_WAN IPV6 VLAN WIREGUARD PBR OPENCLASH OTA HTTPS WAN_FIREWALL; do
	[ "$(value "$key")" = PASS ] || { echo "$key=PASS is required for stable" >&2; exit 1; }
done
for key in HARDWARE_VARIANT SECURE_BOOT_STATE BOOT_SLOT MTD_LAYOUT APPROVER APPROVED_AT; do
	entry=$(value "$key")
	[ -n "$entry" ] || { echo "$key evidence is required" >&2; exit 1; }
	case "$entry" in *TODO*|*UNKNOWN*|*'< '*|*'>'*) echo "$key still contains a placeholder" >&2; exit 1 ;; esac
done
for key in MTD_EVIDENCE_SHA256 TEST_LOG_SHA256 FIRMWARE_SHA256; do
	value "$key" | grep -Eq '^[0-9a-f]{64}$' || { echo "$key must be 64 lowercase hex" >&2; exit 1; }
done
value APPROVED_AT | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || { echo 'APPROVED_AT must be UTC ISO-8601' >&2; exit 1; }
printf 'production gate evidence accepted for %s\n' "$EXPECTED_VERSION"
