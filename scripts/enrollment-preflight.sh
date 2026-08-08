#!/bin/sh
# Read-only first-enrollment safety checks for CompanyWrt on Xiaomi AX9000.
set -eu

usage() {
	cat <<'EOF'
Usage: enrollment-preflight.sh [--expected-version VERSION]

Checks board/target/release/profile/version metadata, root password state,
HTTPS redirect/listener, WAN input policy, clock and free overlay/tmp space.
It never prints password hashes and never changes UCI or device state.
Run locally from an isolated wired LAN; do not perform first enrollment over
Wi-Fi or from the WAN side.
EOF
}

EXPECTED_VERSION=""
while [ "$#" -gt 0 ]; do
	case "$1" in
		--expected-version) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; EXPECTED_VERSION=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

FAILURES=0
WARNINGS=0
board=""
release=""
target=""
pass() { printf 'PASS  %s\n' "$*"; }
warn() { WARNINGS=$((WARNINGS + 1)); printf 'WARN  %s\n' "$*"; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL  %s\n' "$*"; }

DEVICE_ROOT=${COMPANYWRT_DEVICE_ROOT:-}
VERSION_FILE="$DEVICE_ROOT/etc/companywrt/VERSION"
BUILD_CONF="$DEVICE_ROOT/etc/companywrt/build.conf"
SHADOW_FILE="$DEVICE_ROOT/etc/shadow"

if command -v ubus >/dev/null 2>&1 && command -v jsonfilter >/dev/null 2>&1; then
	if board_json=$(ubus call system board 2>/dev/null); then
		board=$(printf '%s\n' "$board_json" | jsonfilter -e '@.board_name' 2>/dev/null || true)
		release=$(printf '%s\n' "$board_json" | jsonfilter -e '@.release.version' 2>/dev/null || true)
		target=$(printf '%s\n' "$board_json" | jsonfilter -e '@.release.target' 2>/dev/null || true)
		if [ "$board" = xiaomi,ax9000-darkyun ]; then pass 'board is xiaomi,ax9000-darkyun'; else fail "board is '${board:-unknown}', expected xiaomi,ax9000-darkyun"; fi
		if [ "$target" = qualcommax/ipq807x ]; then pass 'target is qualcommax/ipq807x'; else fail "target is '${target:-unknown}', expected qualcommax/ipq807x"; fi
		if printf '%s\n' "$release" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then pass "OpenWrt release metadata is $release"; else fail 'OpenWrt release metadata is missing/invalid'; fi
	else
		fail 'ubus call system board failed'
	fi
else
	fail 'ubus and jsonfilter are required for board verification'
fi

if [ -s "$VERSION_FILE" ]; then
	version=$(sed -n '1p' "$VERSION_FILE")
	if printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+-company\.[0-9]+(-(rc|beta)[1-9][0-9]*)?$'; then
		if [ -n "$EXPECTED_VERSION" ] && [ "$version" != "$EXPECTED_VERSION" ]; then
			fail "installed CompanyWrt version $version does not match expected $EXPECTED_VERSION"
		else
			pass "CompanyWrt version is $version"
		fi
	else
		fail 'installed CompanyWrt version is invalid'
	fi
else
	fail "version file is missing: $VERSION_FILE"
fi

if [ -s "$BUILD_CONF" ]; then
	profile=$(awk -F= '$1 == "PROFILE" { print $2; exit }' "$BUILD_CONF")
	build_board=$(awk -F= '$1 == "BOARD" { print $2; exit }' "$BUILD_CONF")
	partition_variant=$(awk -F= '$1 == "PARTITION_VARIANT" { print $2; exit }' "$BUILD_CONF")
	build_release=$(awk -F= '$1 == "RELEASE" { print $2; exit }' "$BUILD_CONF")
	channel=$(awk -F= '$1 == "CHANNEL" { print $2; exit }' "$BUILD_CONF")
	if [ "$profile" = xiaomi_ax9000_darkyun ]; then pass 'image profile is xiaomi_ax9000_darkyun'; else fail "image profile is '${profile:-missing}'"; fi
	if [ -n "$board" ] && [ "$build_board" = "$board" ]; then pass "build board matches running board $board"; else fail "build board '${build_board:-missing}' does not match running board '${board:-unknown}'"; fi
	if [ "$partition_variant" = darkyun-large-ubi-v1 ]; then pass 'partition variant is darkyun-large-ubi-v1'; else fail "partition variant is '${partition_variant:-missing}'"; fi
	if [ -n "$release" ] && [ "$build_release" = "$release" ]; then
		pass "build metadata release matches running OpenWrt $release"
	else
		fail "build release '${build_release:-missing}' does not match running release '${release:-unknown}'"
	fi
	if [ -n "${version:-}" ] && [ "${version%%-company.*}" = "$build_release" ]; then
		pass 'CompanyWrt VERSION base matches build release'
	else
		fail 'CompanyWrt VERSION base does not match build release'
	fi
	channel_matches=0
	case "$channel" in
		rc) printf '%s\n' "${version:-}" | grep -Eq -- '-rc[1-9][0-9]*$' && channel_matches=1 ;;
		beta) printf '%s\n' "${version:-}" | grep -Eq -- '-beta[1-9][0-9]*$' && channel_matches=1 ;;
		stable) printf '%s\n' "${version:-}" | grep -Eq -- '-company\.[0-9]+$' && channel_matches=1 ;;
	esac
	if [ "$channel_matches" -eq 1 ]; then
		pass "image channel is $channel and matches VERSION"
	else
		fail "image channel '${channel:-missing}' does not match VERSION"
	fi
else
	fail "build metadata is missing: $BUILD_CONF"
fi

if [ -r "$SHADOW_FILE" ]; then
	root_field=$(awk -F: '$1 == "root" { print $2; exit }' "$SHADOW_FILE")
	case "$root_field" in
		''|'!'|'!!'|'*') fail 'root password is unset or locked; set a unique random password from the wired LAN' ;;
		*) pass 'root password is set (hash intentionally not displayed)' ;;
	esac
else
	fail "cannot read root password state: $SHADOW_FILE"
fi

if command -v uci >/dev/null 2>&1; then
	redirect=$(uci -q get uhttpd.main.redirect_https 2>/dev/null || true)
	listen_https=$(uci -q get uhttpd.main.listen_https 2>/dev/null || true)
	if [ "$redirect" = 1 ]; then pass 'HTTP requests are configured to redirect to HTTPS'; else fail 'uhttpd.main.redirect_https is not enabled'; fi
	if [ -n "$listen_https" ]; then pass 'uHTTPd has an HTTPS listener configured'; else fail 'uHTTPd HTTPS listener is missing'; fi

	firewall_state=$(uci -q show firewall 2>/dev/null || true)
	wan_section=$(printf '%s\n' "$firewall_state" | awk -F= '$1 ~ /\.name$/ && $2 == "\047wan\047" { sub(/\.name$/, "", $1); print $1; exit }')
	if [ -n "$wan_section" ]; then
		wan_input=$(printf '%s\n' "$firewall_state" | awk -F= -v key="$wan_section.input" '$1 == key { gsub(/\047/, "", $2); print $2; exit }')
		case "$wan_input" in REJECT|DROP) pass "WAN input policy is $wan_input" ;; *) fail "WAN input policy is '${wan_input:-missing}', expected REJECT or DROP" ;; esac
	else
		fail 'firewall WAN zone was not found'
	fi
	for zone in company_unicom company_mobile; do
		zone_input=$(uci -q get "firewall.$zone.input" 2>/dev/null || true)
		case "$zone_input" in
			'') ;;
			REJECT|DROP) pass "$zone input policy is $zone_input" ;;
			*) fail "$zone input policy is $zone_input, expected REJECT or DROP" ;;
		esac
	done
else
	fail 'uci is required for HTTPS/firewall verification'
fi

now=$(date +%s 2>/dev/null || echo 0)
if [ "$now" -ge 1767225600 ] 2>/dev/null; then
	pass "clock is plausibly set ($(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true))"
else
	fail 'clock predates 2026-01-01; fix NTP/time before TLS or OTA'
fi

check_space() {
	path=$1
	minimum=$2
	label=$3
	if [ -d "$path" ]; then
		available=$(df -Pk "$path" 2>/dev/null | awk 'NR == 2 { print $4 }')
		if [ -n "$available" ] && [ "$available" -ge "$minimum" ] 2>/dev/null; then
			pass "$label has ${available} KiB free"
		else
			fail "$label has ${available:-unknown} KiB free; require at least ${minimum} KiB"
		fi
	else
		fail "$label path is missing: $path"
	fi
}

if [ -d "$DEVICE_ROOT/overlay" ]; then
	check_space "$DEVICE_ROOT/overlay" 32768 overlay
else
	fail '/overlay is not mounted; writable persistent storage is required before enrollment'
fi
check_space "$DEVICE_ROOT/tmp" 65536 tmpfs

printf 'NOTE  first enrollment is allowed only from an isolated wired LAN; preserve the official LuCI rescue theme.\n'
printf 'SUMMARY failures=%s warnings=%s\n' "$FAILURES" "$WARNINGS"
[ "$FAILURES" -eq 0 ]
