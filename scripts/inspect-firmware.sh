#!/bin/sh
# Inspect an AX9000 sysupgrade tar and its squashfs root without executing it.
set -eu

ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
IMAGE=""
PACKAGE_MANIFEST=""
REPORT=""
EMBEDDED_KEY_ID=""
HARDWARE_VALIDATION=NOT_PERFORMED_RC_ONLY
PRODUCTION_GATE_SHA256=NONE
HARDWARE_EVIDENCE_ID=NONE
SERIAL_EVIDENCE_ID=NONE
TESTED_FIRMWARE_SHA256=NONE
EXPECTED_VERSION=$(sed -n '1p' "$ROOT/VERSION")

usage() {
	cat <<'EOF'
Usage: inspect-firmware.sh --image FILE --package-manifest FILE --report FILE [options]

Options:
  --embedded-key-id 16HEX
  --hardware-validation NOT_PERFORMED_RC_ONLY|VERIFIED
  --production-gate-sha256 NONE|64HEX
  --hardware-evidence-id NONE|OPAQUE_ID
  --serial-evidence-id NONE|OPAQUE_ID
  --tested-firmware-sha256 NONE|64HEX

Extracts the sysupgrade tar into a temporary directory, lists/reads the
squashfs root, and verifies required packages, CompanyWrt files, public key,
version/build metadata and safe first-boot defaults. It never flashes.
EOF
}

while [ "$#" -gt 0 ]; do
	case "$1" in
		--image) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; IMAGE=$2; shift 2 ;;
		--package-manifest) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PACKAGE_MANIFEST=$2; shift 2 ;;
		--report) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; REPORT=$2; shift 2 ;;
		--embedded-key-id) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; EMBEDDED_KEY_ID=$2; shift 2 ;;
		--hardware-validation) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; HARDWARE_VALIDATION=$2; shift 2 ;;
		--production-gate-sha256) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; PRODUCTION_GATE_SHA256=$2; shift 2 ;;
		--hardware-evidence-id) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; HARDWARE_EVIDENCE_ID=$2; shift 2 ;;
		--serial-evidence-id) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; SERIAL_EVIDENCE_ID=$2; shift 2 ;;
		--tested-firmware-sha256) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; TESTED_FIRMWARE_SHA256=$2; shift 2 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done
[ -f "$IMAGE" ] || { echo "firmware image not found: $IMAGE" >&2; exit 1; }
[ -s "$PACKAGE_MANIFEST" ] || { echo "package manifest not found: $PACKAGE_MANIFEST" >&2; exit 1; }
[ -n "$REPORT" ] || { usage >&2; exit 2; }
printf '%s\n' "$EMBEDDED_KEY_ID" | grep -Eq '^[0-9a-f]{16}$' || { echo 'embedded key ID must be 16 lowercase hex' >&2; exit 1; }
case "$HARDWARE_VALIDATION" in
	NOT_PERFORMED_RC_ONLY)
		[ "$PRODUCTION_GATE_SHA256" = NONE ] && [ "$HARDWARE_EVIDENCE_ID" = NONE ] && \
			[ "$SERIAL_EVIDENCE_ID" = NONE ] && [ "$TESTED_FIRMWARE_SHA256" = NONE ] || {
			echo 'RC inspection cannot carry production evidence values' >&2
			exit 1
		}
		;;
	VERIFIED)
		printf '%s\n' "$PRODUCTION_GATE_SHA256" "$TESTED_FIRMWARE_SHA256" | \
			awk 'length($0) != 64 || $0 !~ /^[0-9a-f]+$/ { exit 1 }' || { echo 'verified inspection requires 64-hex gate and tested firmware digests' >&2; exit 1; }
		printf '%s\n' "$HARDWARE_EVIDENCE_ID" "$SERIAL_EVIDENCE_ID" | \
			awk 'length($0) < 3 || length($0) > 128 || $0 !~ /^[A-Za-z0-9][A-Za-z0-9._:-]+$/ { exit 1 }' || { echo 'verified inspection requires safe opaque hardware and serial evidence IDs' >&2; exit 1; }
		;;
	*) echo 'invalid hardware validation state' >&2; exit 1 ;;
esac

if [ -n "${UNSQUASHFS:-}" ]; then
	UNSQUASHFS_BIN=$UNSQUASHFS
elif command -v unsquashfs >/dev/null 2>&1; then
	UNSQUASHFS_BIN=$(command -v unsquashfs)
elif command -v unsquashfs4 >/dev/null 2>&1; then
	UNSQUASHFS_BIN=$(command -v unsquashfs4)
else
	echo 'unsquashfs is required for firmware content inspection' >&2
	exit 1
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-inspect.XXXXXX")
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT INT TERM

tar tf "$IMAGE" > "$TMP/tar.list"
[ "$(wc -l < "$TMP/tar.list" | tr -d '[:space:]')" -eq 4 ] || { echo 'sysupgrade archive must contain exactly its directory, CONTROL, kernel and root' >&2; exit 1; }
tar tvf "$IMAGE" | awk 'substr($1, 1, 1) != "d" && substr($1, 1, 1) != "-" { exit 1 }' || { echo 'sysupgrade archive contains a non-file/non-directory entry' >&2; exit 1; }
awk '
	/^\// || /(^|\/)\.\.($|\/)/ { print "unsafe sysupgrade tar path: " $0 > "/dev/stderr"; exit 1 }
	NF { split($0, p, "/"); if (top == "") top = p[1]; else if (top != p[1]) exit 1 }
	END { if (top != "sysupgrade-xiaomi_ax9000") exit 1 }
' "$TMP/tar.list" || { echo 'unexpected/unsafe sysupgrade archive layout' >&2; exit 1; }
for member in CONTROL kernel root; do
	grep -qx "sysupgrade-xiaomi_ax9000/$member" "$TMP/tar.list" || { echo "missing sysupgrade member: $member" >&2; exit 1; }
done
tar xf "$IMAGE" -C "$TMP"
ROOTFS="$TMP/sysupgrade-xiaomi_ax9000/root"
file "$ROOTFS" | grep -qi 'Squashfs filesystem' || { echo 'sysupgrade root is not squashfs' >&2; exit 1; }
"$UNSQUASHFS_BIN" -ll "$ROOTFS" > "$TMP/rootfs.list"
if grep -Eq '/\.DS_Store([[:space:]]|$)' "$TMP/rootfs.list"; then
	echo 'host Finder metadata leaked into the firmware rootfs' >&2
	exit 1
fi

rootfs_has() {
	path=${1#/}
	grep -Eq "squashfs-root/$path( -> .*|$)" "$TMP/rootfs.list"
}

rootfs_cat() {
	path=${1#/}
	"$UNSQUASHFS_BIN" -cat "$ROOTFS" "$path" 2>/dev/null
}

REQUIRED_FILES='
/etc/companywrt/VERSION
/etc/companywrt/build.conf
/etc/companywrt/keys/release.pub
/etc/shadow
/etc/config/collectd
/etc/config/firewall
/etc/board.d/02_network
/bin/config_generate
/etc/uci-defaults/99-companywrt
/usr/share/company/company-network
/usr/share/company/ota-common.sh
/usr/share/company/ota-check
/usr/share/company/ota-apply
/usr/share/company/enrollment-preflight
/usr/share/company/LICENSE
/usr/share/company/NOTICE
/usr/share/company/CUSTOM-COMPONENTS.manifest
/usr/share/company/sqm-mobile-template
/usr/lib/lua/luci/view/company/dashboard.htm
/www/luci-static/company/css/company.css
'
for path in $REQUIRED_FILES; do
	rootfs_has "$path" || { echo "required rootfs file missing: $path" >&2; exit 1; }
done

[ "$(rootfs_cat /etc/companywrt/VERSION | sed -n '1p')" = "$EXPECTED_VERSION" ] || { echo 'embedded VERSION mismatch' >&2; exit 1; }
rootfs_cat /etc/companywrt/build.conf > "$TMP/build.conf"
grep -qx 'PROFILE=xiaomi_ax9000' "$TMP/build.conf" || { echo 'embedded PROFILE mismatch' >&2; exit 1; }
grep -qx 'RELEASE=25.12.5' "$TMP/build.conf" || { echo 'embedded OpenWrt RELEASE mismatch' >&2; exit 1; }
[ "$(wc -l < "$TMP/build.conf" | tr -d '[:space:]')" -eq 3 ] || { echo 'embedded build metadata has unexpected/self-referential fields' >&2; exit 1; }
rootfs_cat /etc/companywrt/keys/release.pub > "$TMP/release.pub"
cmp "$ROOT/keys/companywrt-release.pub" "$TMP/release.pub" || { echo 'embedded release public key mismatch' >&2; exit 1; }
rootfs_cat /etc/shadow > "$TMP/shadow"
[ "$(awk -F: '$1 == "root" { count++ } END { print count + 0 }' "$TMP/shadow")" -eq 1 ] || { echo 'rootfs /etc/shadow must contain exactly one root entry' >&2; exit 1; }
ROOT_PASSWORD_FIELD=$(awk -F: '$1 == "root" { print $2; exit }' "$TMP/shadow")
case "$ROOT_PASSWORD_FIELD" in
	'') ROOT_PASSWORD_STATE=EMPTY ;;
	*[!*!]*) echo 'rootfs contains a preconfigured root password hash; release rejected' >&2; exit 1 ;;
	*) ROOT_PASSWORD_STATE=LOCKED ;;
esac
rootfs_cat /etc/uci-defaults/99-companywrt > "$TMP/firstboot"
grep -q "uhttpd.main.redirect_https='1'" "$TMP/firstboot" || { echo 'HTTPS redirect is missing from first boot' >&2; exit 1; }
grep -q '/etc/init.d/collectd disable' "$TMP/firstboot" || { echo 'collectd is not disabled pending monitoring enrollment' >&2; exit 1; }
if grep -Eqi '(password|passwd).*(=|set).*["'"'][^"'"']+["'"']|firewall\..*input=.ACCEPT' "$TMP/firstboot"; then
	echo 'first boot appears to embed a password or allow WAN input' >&2
	exit 1
fi
rootfs_cat /etc/config/collectd > "$TMP/collectd"
awk '
	$1 == "config" && $2 == "plugin" { plugin = $3; gsub(/\047/, "", plugin) }
	$1 == "option" && $2 == "enable" && $3 != "\047" "0" "\047" { print "enabled collectd plugin: " plugin > "/dev/stderr"; exit 1 }
	$1 == "config" && ($2 == "network_listen" || $2 == "network_server") { print "collectd network endpoint is preconfigured" > "/dev/stderr"; exit 1 }
' "$TMP/collectd" || exit 1
rootfs_cat /etc/config/firewall > "$TMP/firewall"
awk '
	function clean(value) { gsub(/\047/, "", value); return value }
	function finish() {
		if (kind == "zone" && name == "wan" && input == "REJECT" && output == "ACCEPT" && forward == "DROP" && wan && wan6) found = 1
	}
	$1 == "config" { finish(); kind = clean($2); name = input = output = forward = ""; wan = wan6 = 0; next }
	$1 == "option" && $2 == "name" { name = clean($3) }
	$1 == "option" && $2 == "input" { input = clean($3) }
	$1 == "option" && $2 == "output" { output = clean($3) }
	$1 == "option" && $2 == "forward" { forward = clean($3) }
	$1 == "list" && $2 == "network" && clean($3) == "wan" { wan = 1 }
	$1 == "list" && $2 == "network" && clean($3) == "wan6" { wan6 = 1 }
	END { finish(); exit !found }
' "$TMP/firewall" || { echo 'default WAN/WAN6 firewall zone is not reject/drop' >&2; exit 1; }
for rule in Allow-DHCP-Renew Allow-Ping Allow-DHCPv6 Allow-ICMPv6-Input Allow-ICMPv6-Forward; do
	grep -Eq "option[[:space:]]+name[[:space:]]+$rule$" "$TMP/firewall" || { echo "default firewall rule missing: $rule" >&2; exit 1; }
done
rootfs_cat /etc/board.d/02_network > "$TMP/board-network"
grep -q 'xiaomi,ax9000' "$TMP/board-network" || { echo 'AX9000 board network mapping is missing' >&2; exit 1; }
grep -q 'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan"' "$TMP/board-network" || { echo 'AX9000 DSA LAN/WAN mapping is missing' >&2; exit 1; }
rootfs_cat /bin/config_generate > "$TMP/config-generate"
grep -q "set network.loopback='interface'" "$TMP/config-generate" || { echo 'default loopback generation is missing' >&2; exit 1; }
grep -Fq "set network.\${1}6.device=" "$TMP/config-generate" || { echo 'default WAN6 generation is missing' >&2; exit 1; }
grep -q "set network.@device\[-1\].type='bridge'" "$TMP/config-generate" || { echo 'default DSA bridge generation is missing' >&2; exit 1; }

for package in firewall4 pbr luci-app-pbr luci-ssl-openssl usign jsonfilter kmod-wireguard wireguard-tools luci-proto-wireguard logd collectd collectd-mod-network; do
	grep -Eq "^$package - [^[:space:]]+" "$PACKAGE_MANIFEST" || { echo "required package missing from manifest: $package" >&2; exit 1; }
done
if grep -Eq '^mwan3 - |^luci-app-sqm - |^sqm-scripts - ' "$PACKAGE_MANIFEST"; then
	echo 'forbidden/non-base package present (mwan3 or optional SQM)' >&2
	exit 1
fi
for component in luci-app-company-overlay luci-theme-company-overlay companywrt-device-overlay companywrt-operations-scripts; do
	rootfs_cat /usr/share/company/CUSTOM-COMPONENTS.manifest | grep -Fq "$component" || { echo "custom component inventory missing: $component" >&2; exit 1; }
done

IMAGE_DIGEST=$(sha256sum "$IMAGE" | awk '{print $1}')
if [ "$HARDWARE_VALIDATION" = VERIFIED ] && [ "$IMAGE_DIGEST" != "$TESTED_FIRMWARE_SHA256" ]; then
	echo 'verified hardware evidence digest does not match the inspected firmware image' >&2
	exit 1
fi

{
	printf 'CompanyWrt firmware content inspection\n'
	printf 'image=%s\n' "$(basename "$IMAGE")"
	printf 'image_sha256=%s\n' "$IMAGE_DIGEST"
	printf 'version=%s\nprofile=xiaomi_ax9000\nboard=xiaomi,ax9000\n' "$EXPECTED_VERSION"
	printf 'sysupgrade_layout=PASS\nsquashfs_root=PASS\nrequired_files=PASS\nrequired_packages=PASS\n'
	printf 'https_redirect=PASS\nwan_accept_rule_embedded=NO\ndefault_password_embedded=NO\n'
	printf 'root_password_state=%s\nembedded_usign_key_id=%s\n' "$ROOT_PASSWORD_STATE" "$EMBEDDED_KEY_ID"
	printf 'collectd_plugins_default=DISABLED\ncollectd_network_endpoint=NONE\n'
	printf 'loopback_dsa_wan6_generation=PRESERVED\ndefault_firewall_rules=PRESERVED\nwan_wan6_input=REJECT\n'
	printf 'custom_overlay_components_inventoried=PASS\n'
	printf 'hardware_validation=%s\n' "$HARDWARE_VALIDATION"
	printf 'production_gate_sha256=%s\n' "$PRODUCTION_GATE_SHA256"
	printf 'hardware_evidence_id=%s\n' "$HARDWARE_EVIDENCE_ID"
	printf 'serial_evidence_id=%s\n' "$SERIAL_EVIDENCE_ID"
	printf 'tested_firmware_sha256=%s\n' "$TESTED_FIRMWARE_SHA256"
} > "$REPORT"
cat "$REPORT"
