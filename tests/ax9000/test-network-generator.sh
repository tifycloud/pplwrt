#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-network-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM

OUT=$("$ROOT/scripts/company-network.sh" plan \
	--unicom-device wan \
	--mobile-device lan4 \
	--office-cidr 192.168.50.1/24 \
	--server 192.168.50.10 \
	--employee 192.168.50.20/32 \
	--mobile-dest uploads.example.com \
	--unicom-dest 203.0.113.0/24 \
	--mobile-port tcp:443 \
	--unicom-port udp:53 \
	--output "$TMP/plan")
[ "$OUT" = "$TMP/plan" ]

BATCH="$OUT/uci.batch"
grep -q "set network.unicom.device='wan'" "$BATCH"
grep -q "set network.mobile.device='lan4'" "$BATCH"
grep -q "set network.unicom.metric='10'" "$BATCH"
grep -q "set network.mobile.metric='20'" "$BATCH"
grep -q "set pbr.company_server_1.src_addr='192.168.50.10'" "$BATCH"
grep -q "set pbr.company_employee_1.interface='mobile'" "$BATCH"
grep -q "set pbr.company_mobile_dest_1.dest_addr='uploads.example.com'" "$BATCH"
grep -q "set pbr.company_unicom_dest_1.dest_addr='203.0.113.0/24'" "$BATCH"
grep -q "set pbr.company_mobile_port_1.dest_port='443'" "$BATCH"
grep -q "set pbr.company_office_default.src_addr='192.168.50.0/24'" "$BATCH"
grep -q "set pbr.company_office_default.interface='unicom'" "$BATCH"
grep -q "set firewall.company_unicom.input='REJECT'" "$BATCH"
grep -q "set firewall.company_mobile.input='REJECT'" "$BATCH"
grep -q "resolver_set='dnsmasq.nftset'" "$BATCH"

for forbidden in 'uci import' 'uci commit' '/etc/init.d/' 'delete network' 'delete firewall' 'delete pbr'; do
	if grep -Fq "$forbidden" "$BATCH"; then
		echo "unsafe command in plan: $forbidden" >&2
		exit 1
	fi
done
grep -q 'Existing loopback, DSA bridge/ports, default WAN/WAN6' "$OUT/REVIEW.md"
grep -q 'does not provide a live-apply command' "$OUT/REVIEW.md"

if "$ROOT/scripts/company-network.sh" plan --unicom-device wan --mobile-device lan4 \
	--output "$OUT" >"$TMP/reuse.out" 2>"$TMP/reuse.err"; then
	echo 'existing network plan directory unexpectedly accepted' >&2
	exit 1
fi
grep -q 'output directory must not already exist' "$TMP/reuse.err"

expect_reject() {
	name=$1
	shift
	if "$ROOT/scripts/company-network.sh" "$@" >"$TMP/$name.out" 2>"$TMP/$name.err"; then
		echo "$name unexpectedly succeeded" >&2
		exit 1
	fi
}

expect_reject apply-disabled apply --unicom-device wan --mobile-device lan4
grep -q 'live apply/rollback is disabled' "$TMP/apply-disabled.err"
expect_reject duplicate plan --unicom-device wan --mobile-device wan
expect_reject iface-injection plan --unicom-device "wan';reboot" --mobile-device lan4
expect_reject bad-cidr plan --unicom-device wan --mobile-device lan4 --office-cidr 192.168.1.999/24
expect_reject bad-prefix plan --unicom-device wan --mobile-device lan4 --office-cidr 192.168.1.0/033
expect_reject source-injection plan --unicom-device wan --mobile-device lan4 --employee '192.168.1.2;reboot'
expect_reject domain-injection plan --unicom-device wan --mobile-device lan4 --mobile-dest 'example.com;reboot'
expect_reject port-injection plan --unicom-device wan --mobile-device lan4 --mobile-port 'tcp:443;reboot'
expect_reject static-pair plan --unicom-device wan --mobile-device lan4 --unicom-address 198.51.100.2/24
expect_reject gateway-subnet plan --unicom-device wan --mobile-device lan4 --unicom-address 198.51.100.2/24 --unicom-gateway 203.0.113.1
expect_reject gateway-duplicate plan --unicom-device wan --mobile-device lan4 --unicom-address 198.51.100.2/24 --unicom-gateway 198.51.100.2
expect_reject duplicate-static plan --unicom-device wan --mobile-device lan4 \
	--unicom-address 198.51.100.2/24 --unicom-gateway 198.51.100.1 \
	--mobile-address 198.51.100.3/24 --mobile-gateway 198.51.100.1
expect_reject overlapping-static plan --unicom-device wan --mobile-device lan4 \
	--unicom-address 198.51.100.2/24 --unicom-gateway 198.51.100.1 \
	--mobile-address 198.51.100.130/25 --mobile-gateway 198.51.100.129
expect_reject office-overlap plan --unicom-device wan --mobile-device lan4 \
	--office-cidr 192.168.50.0/24 --unicom-address 192.168.50.2/24 --unicom-gateway 192.168.50.1

STATIC=$("$ROOT/scripts/company-network.sh" plan \
	--unicom-device wan --mobile-device lan4 \
	--unicom-address 198.51.100.2/24 --unicom-gateway 198.51.100.1 \
	--mobile-address 203.0.113.2/24 --mobile-gateway 203.0.113.1 \
	--output "$TMP/static")
grep -q "set network.unicom.proto='static'" "$STATIC/uci.batch"
grep -q "set network.mobile.gateway='203.0.113.1'" "$STATIC/uci.batch"

echo 'network plan validation and non-destructive UCI generation: ok'
