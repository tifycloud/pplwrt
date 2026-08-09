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
		if [ "$PRODUCTION_GATE_SHA256" != NONE ] || [ "$HARDWARE_EVIDENCE_ID" != NONE ] || \
			[ "$SERIAL_EVIDENCE_ID" != NONE ] || [ "$TESTED_FIRMWARE_SHA256" != NONE ]; then
			echo 'RC inspection cannot carry production evidence values' >&2
			exit 1
		fi
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

if [ -n "${DUMPIMAGE:-}" ]; then
	DUMPIMAGE_BIN=$DUMPIMAGE
elif command -v dumpimage >/dev/null 2>&1; then
	DUMPIMAGE_BIN=$(command -v dumpimage)
else
	echo 'dumpimage is required for embedded kernel FIT inspection' >&2
	exit 1
fi
if [ -n "${DTC:-}" ]; then
	DTC_BIN=$DTC
elif command -v dtc >/dev/null 2>&1; then
	DTC_BIN=$(command -v dtc)
else
	echo 'dtc is required for embedded device-tree inspection' >&2
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
	END { if (top != "sysupgrade-xiaomi_ax9000_darkyun") exit 1 }
' "$TMP/tar.list" || { echo 'unexpected/unsafe sysupgrade archive layout' >&2; exit 1; }
for member in CONTROL kernel root; do
	grep -qx "sysupgrade-xiaomi_ax9000_darkyun/$member" "$TMP/tar.list" || { echo "missing sysupgrade member: $member" >&2; exit 1; }
done
tar xf "$IMAGE" -C "$TMP"
SYSUPGRADE_DIR="$TMP/sysupgrade-xiaomi_ax9000_darkyun"
ROOTFS="$SYSUPGRADE_DIR/root"
KERNEL="$SYSUPGRADE_DIR/kernel"

"$DUMPIMAGE_BIN" -l "$KERNEL" > "$TMP/fit.list"
FDT_INDEXES=$(sed -n 's/^[[:space:]]*Image \([0-9][0-9]*\) (fdt[^)]*)$/\1/p' "$TMP/fit.list")
[ "$(printf '%s\n' "$FDT_INDEXES" | sed '/^$/d' | wc -l | tr -d '[:space:]')" -eq 1 ] || { echo 'kernel FIT must contain exactly one fdt image' >&2; exit 1; }
FDT_INDEX=$(printf '%s\n' "$FDT_INDEXES" | sed -n '1p')
"$DUMPIMAGE_BIN" -T flat_dt -p "$FDT_INDEX" -o "$TMP/kernel.dtb" "$KERNEL"
[ -s "$TMP/kernel.dtb" ] || { echo 'failed to extract kernel device tree' >&2; exit 1; }
"$DTC_BIN" -I dtb -O dts "$TMP/kernel.dtb" > "$TMP/kernel.dts"
grep -Fq 'xiaomi,ax9000-darkyun' "$TMP/kernel.dts" || { echo 'kernel DT does not identify the Darkyun AX9000 board' >&2; exit 1; }
grep -Fq 'root=/dev/ubiblock0_1' "$TMP/kernel.dts" || { echo 'kernel DT does not boot the single-UBI rootfs volume' >&2; exit 1; }
grep -Eq 'reg = <0x0*1180000 0x0*e800000>;' "$TMP/kernel.dts" || { echo 'kernel DT rootfs partition is not 0x01180000+0x0e800000' >&2; exit 1; }
grep -Eq 'reg = <0x0*f980000 0x0*80000>;' "$TMP/kernel.dts" || { echo 'kernel DT cfg_bak partition is not 0x0f980000+0x00080000' >&2; exit 1; }
if grep -Fq 'ubi_kernel' "$TMP/kernel.dts"; then
	echo 'kernel DT still contains the incompatible split-layout ubi_kernel partition' >&2
	exit 1
fi
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
/etc/companywrt/device-layout.json
/etc/companywrt/keys/release.pub
/etc/shadow
/etc/config/firewall
/etc/board.d/02_network
/bin/config_generate
/etc/uci-defaults/99-companywrt
/usr/share/company/company-network
/usr/share/company/ota-common.sh
/usr/share/company/ota-check
/usr/share/company/ota-apply
/usr/share/company/enrollment-preflight
/usr/share/company/ax9000-darkyun-preflight
/usr/share/company/memory-report
/usr/share/company/LICENSE
/usr/share/company/NOTICE
/usr/share/company/CUSTOM-COMPONENTS.manifest
/usr/share/company/sqm-mobile-template
/www/luci-static/resources/view/company/dashboard.js
/www/luci-static/resources/view/company/setup.js
/www/luci-static/liquid/cascade.css
/www/luci-static/liquid/main.js
/www/luci-static/liquid/logo.svg
/www/luci-static/resources/menu-liquid.js
/www/luci-static/resources/view/liquid/sysauth.js
/usr/share/ucode/luci/template/themes/liquid/header.ut
/usr/share/ucode/luci/template/themes/liquid/footer.ut
/usr/share/ucode/luci/template/themes/liquid/sysauth.ut
/usr/share/licenses/luci-theme-liquid/LICENSE
/usr/share/rpcd/ucode/luci-theme-liquid
/usr/share/rpcd/acl.d/luci-theme-liquid.json
'
for path in $REQUIRED_FILES; do
	rootfs_has "$path" || { echo "required rootfs file missing: $path" >&2; exit 1; }
done

[ "$(rootfs_cat /etc/companywrt/VERSION | sed -n '1p')" = "$EXPECTED_VERSION" ] || { echo 'embedded VERSION mismatch' >&2; exit 1; }
rootfs_cat /etc/companywrt/build.conf > "$TMP/build.conf"
grep -qx 'PROFILE=xiaomi_ax9000_darkyun' "$TMP/build.conf" || { echo 'embedded PROFILE mismatch' >&2; exit 1; }
grep -qx 'BOARD=xiaomi,ax9000-darkyun' "$TMP/build.conf" || { echo 'embedded BOARD mismatch' >&2; exit 1; }
grep -qx 'PARTITION_VARIANT=darkyun-large-ubi-v1' "$TMP/build.conf" || { echo 'embedded partition variant mismatch' >&2; exit 1; }
grep -qx 'RELEASE=25.12.5' "$TMP/build.conf" || { echo 'embedded OpenWrt RELEASE mismatch' >&2; exit 1; }
[ "$(wc -l < "$TMP/build.conf" | tr -d '[:space:]')" -eq 5 ] || { echo 'embedded build metadata has unexpected/self-referential fields' >&2; exit 1; }
rootfs_cat /etc/companywrt/device-layout.json > "$TMP/device-layout.json"
cmp "$ROOT/devices/ax9000/darkyun-large-ubi.json" "$TMP/device-layout.json" || { echo 'embedded Darkyun device specification mismatch' >&2; exit 1; }
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
grep -q "luci.main.mediaurlbase='/luci-static/liquid'" "$TMP/firstboot" || { echo 'Liquid is not the first-boot theme' >&2; exit 1; }
if grep -Eqi '(password|passwd).*(=|set).*["'"'][^"'"']+["'"']|firewall\..*input=.ACCEPT' "$TMP/firstboot"; then
	echo 'first boot appears to embed a password or allow WAN input' >&2
	exit 1
fi
if rootfs_has /etc/config/collectd; then
	echo 'collectd config unexpectedly embedded in lean base firmware' >&2
	exit 1
fi
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
grep -q 'xiaomi,ax9000-darkyun' "$TMP/board-network" || { echo 'Darkyun AX9000 board network mapping is missing' >&2; exit 1; }
grep -q 'ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan"' "$TMP/board-network" || { echo 'AX9000 DSA LAN/WAN mapping is missing' >&2; exit 1; }
rootfs_cat /bin/config_generate > "$TMP/config-generate"
grep -q "set network.loopback='interface'" "$TMP/config-generate" || { echo 'default loopback generation is missing' >&2; exit 1; }
grep -Fq "set network.\${1}6.device=" "$TMP/config-generate" || { echo 'default WAN6 generation is missing' >&2; exit 1; }
grep -q "set network.@device\[-1\].type='bridge'" "$TMP/config-generate" || { echo 'default DSA bridge generation is missing' >&2; exit 1; }

for package in firewall4 pbr luci-app-pbr luci-ssl-openssl luci-theme-liquid usign jsonfilter kmod-wireguard wireguard-tools luci-proto-wireguard logd dnsmasq-full curl ca-bundle ip-full; do
	grep -Eq "^$package - [^[:space:]]+" "$PACKAGE_MANIFEST" || { echo "required package missing from manifest: $package" >&2; exit 1; }
done
if grep -Eq '^(mwan3|luci-app-sqm|sqm-scripts|luci-app-openclash|openclash|mihomo|ruby|ruby-yaml|collectd|collectd-mod-[^ ]+|bash|kmod-tun|kmod-nft-tproxy|luci-compat) - ' "$PACKAGE_MANIFEST"; then
	echo 'forbidden/non-base package present (optional monitoring, proxy runtime, SQM, mwan3, OpenClash or Mihomo)' >&2
	exit 1
fi
for path in /etc/config/openclash /etc/openclash /usr/share/openclash /usr/bin/mihomo /usr/bin/clash; do
	if rootfs_has "$path"; then
		echo "OpenClash/Mihomo payload unexpectedly embedded in base firmware: $path" >&2
		exit 1
	fi
done
for component in luci-app-company-overlay luci-theme-liquid-company-patch companywrt-device-overlay companywrt-operations-scripts; do
	rootfs_cat /usr/share/company/CUSTOM-COMPONENTS.manifest | grep -Fq "$component" || { echo "custom component inventory missing: $component" >&2; exit 1; }
done

rootfs_cat /usr/share/ucode/luci/template/themes/liquid/header.ut > "$TMP/liquid-header.ut"
rootfs_cat /www/luci-static/liquid/main.js > "$TMP/liquid-main.js"
rootfs_cat /www/luci-static/resources/view/company/dashboard.js > "$TMP/company-dashboard.js"
grep -Fq '胖胖龙专用路由器' "$TMP/liquid-header.ut" || { echo 'Liquid theme is missing the CompanyWrt product name' >&2; exit 1; }
grep -Fq '胖胖龙专用路由器' "$TMP/company-dashboard.js" || { echo 'dashboard is missing the CompanyWrt product name' >&2; exit 1; }
if grep -Eqi 'www\.bing\.com|bing-wallpaper|wget|system\(' "$TMP/liquid-header.ut" "$TMP/liquid-main.js"; then
	echo 'Liquid runtime still contains external wallpaper or shell execution logic' >&2
	exit 1
fi
for path in /www/liquid-cache /usr/share/ucode/luci/controller/liquid.uc /usr/share/luci/menu.d/liquid.json; do
	if rootfs_has "$path"; then
		echo "unsafe/deprecated Liquid runtime path unexpectedly embedded: $path" >&2
		exit 1
	fi
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
	printf 'version=%s\nprofile=xiaomi_ax9000_darkyun\nboard=xiaomi,ax9000-darkyun\n' "$EXPECTED_VERSION"
	printf 'partition_variant=darkyun-large-ubi-v1\nkernel_dtb_layout=PASS\n'
	printf 'sysupgrade_layout=PASS\nsquashfs_root=PASS\nrequired_files=PASS\nrequired_packages=PASS\n'
	printf 'https_redirect=PASS\nwan_accept_rule_embedded=NO\ndefault_password_embedded=NO\n'
	printf 'root_password_state=%s\nembedded_usign_key_id=%s\n' "$ROOT_PASSWORD_STATE" "$EMBEDDED_KEY_ID"
	printf 'collectd_preinstalled=NO\nmemory_metric=MEMAVAILABLE\n'
	printf 'openclash_preinstalled=NO\nmihomo_preinstalled=NO\n'
	printf 'liquid_theme_compiled=PASS\nliquid_external_wallpaper=REMOVED\nproduct_name=胖胖龙专用路由器\n'
	printf 'loopback_dsa_wan6_generation=PRESERVED\ndefault_firewall_rules=PRESERVED\nwan_wan6_input=REJECT\n'
	printf 'custom_overlay_components_inventoried=PASS\n'
	printf 'hardware_validation=%s\n' "$HARDWARE_VALIDATION"
	printf 'production_gate_sha256=%s\n' "$PRODUCTION_GATE_SHA256"
	printf 'hardware_evidence_id=%s\n' "$HARDWARE_EVIDENCE_ID"
	printf 'serial_evidence_id=%s\n' "$SERIAL_EVIDENCE_ID"
	printf 'tested_firmware_sha256=%s\n' "$TESTED_FIRMWARE_SHA256"
} > "$REPORT"
cat "$REPORT"
