#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-preflight-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
MOCK="$TMP/mock-bin"
DEVICE="$TMP/device"
mkdir -p "$MOCK" "$DEVICE/etc/companywrt" "$DEVICE/overlay" "$DEVICE/tmp"

cat > "$MOCK/ubus" <<'EOF'
#!/bin/sh
[ "$*" = 'call system board' ] || exit 1
echo '{"board_name":"xiaomi,ax9000-darkyun","release":{"version":"25.12.5","target":"qualcommax/ipq807x"}}'
EOF
cat > "$MOCK/jsonfilter" <<'EOF'
#!/bin/sh
[ "$1" = -e ] || exit 2
case "$2" in
	@.board_name) echo xiaomi,ax9000-darkyun ;;
	@.release.version) echo 25.12.5 ;;
	@.release.target) echo qualcommax/ipq807x ;;
	*) exit 1 ;;
esac
EOF
cat > "$MOCK/uci" <<'EOF'
#!/bin/sh
[ "$1" = -q ] || exit 2
case "$2:$3" in
	get:uhttpd.main.redirect_https) echo 1 ;;
	get:uhttpd.main.listen_https) echo '0.0.0.0:443 [::]:443' ;;
	get:firewall.company_unicom.input|get:firewall.company_mobile.input) echo REJECT ;;
	show:firewall) cat <<'STATE'
firewall.@defaults[0]=defaults
firewall.@defaults[0].input='REJECT'
firewall.@zone[0]=zone
firewall.@zone[0].name='lan'
firewall.@zone[0].input='ACCEPT'
firewall.@zone[1]=zone
firewall.@zone[1].name='wan'
firewall.@zone[1].input='REJECT'
STATE
		;;
	*) exit 1 ;;
esac
EOF
chmod 0755 "$MOCK"/*

cat > "$DEVICE/etc/companywrt/build.conf" <<'EOF'
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
RELEASE=25.12.5
CHANNEL=rc
EOF
printf '25.12.5-company.2-rc1\n' > "$DEVICE/etc/companywrt/VERSION"
cat > "$DEVICE/etc/shadow" <<'EOF'
root:$6$fixture$not-a-real-password-hash:20000:0:99999:7:::
EOF

PATH="$MOCK:$PATH" COMPANYWRT_DEVICE_ROOT="$DEVICE" "$ROOT/scripts/enrollment-preflight.sh" \
	--expected-version 25.12.5-company.2-rc1 > "$TMP/pass.out"
grep -q 'PASS  board is xiaomi,ax9000-darkyun' "$TMP/pass.out"
grep -q 'PASS  partition variant is darkyun-large-ubi-v1' "$TMP/pass.out"
grep -q 'PASS  HTTP requests are configured to redirect to HTTPS' "$TMP/pass.out"
grep -q 'PASS  WAN input policy is REJECT' "$TMP/pass.out"
grep -q 'build metadata release matches running OpenWrt 25.12.5' "$TMP/pass.out"
grep -q 'VERSION base matches build release' "$TMP/pass.out"
grep -q 'root password is set (hash intentionally not displayed)' "$TMP/pass.out"
grep -q 'SUMMARY failures=0' "$TMP/pass.out"
if grep -Fq "\$6\$fixture" "$TMP/pass.out"; then
	echo 'preflight leaked a password hash' >&2
	exit 1
fi

printf 'root::20000:0:99999:7:::\n' > "$DEVICE/etc/shadow"
if PATH="$MOCK:$PATH" COMPANYWRT_DEVICE_ROOT="$DEVICE" "$ROOT/scripts/enrollment-preflight.sh" \
	--expected-version 25.12.5-company.2-rc1 > "$TMP/fail.out"; then
	echo 'unset root password unexpectedly passed enrollment' >&2
	exit 1
fi
grep -q 'FAIL  root password is unset or locked' "$TMP/fail.out"

cat > "$DEVICE/etc/shadow" <<'EOF'
root:$6$fixture$not-a-real-password-hash:20000:0:99999:7:::
EOF
sed 's/^RELEASE=.*/RELEASE=25.12.4/' "$DEVICE/etc/companywrt/build.conf" > "$TMP/bad-build.conf"
cp "$TMP/bad-build.conf" "$DEVICE/etc/companywrt/build.conf"
if PATH="$MOCK:$PATH" COMPANYWRT_DEVICE_ROOT="$DEVICE" "$ROOT/scripts/enrollment-preflight.sh" \
	--expected-version 25.12.5-company.2-rc1 > "$TMP/release-fail.out"; then
	echo 'mismatched embedded/running release unexpectedly passed enrollment' >&2
	exit 1
fi
grep -q "does not match running release" "$TMP/release-fail.out"

echo 'read-only enrollment preflight board/version/password/HTTPS/firewall/time/space gates: ok'
