#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/companywrt-inspector-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT INT TERM
MOCK="$TMP/mock-bin"
FIXTURE_ROOT="$TMP/rootfs-fixture"
ARCHIVE_ROOT="$TMP/archive/sysupgrade-xiaomi_ax9000"
mkdir -p "$MOCK" "$FIXTURE_ROOT" "$ARCHIVE_ROOT"

cat > "$MOCK/file" <<'EOF'
#!/bin/sh
printf '%s: Squashfs filesystem\n' "$1"
EOF
cat > "$MOCK/unsquashfs" <<'EOF'
#!/bin/sh
set -eu
case "$1" in
	-ll)
		find "$FIXTURE_ROOT" -mindepth 1 -print | LC_ALL=C sort | while IFS= read -r path; do
			relative=${path#"$FIXTURE_ROOT"/}
			printf '%s squashfs-root/%s\n' '-rw-r--r-- root/root' "$relative"
		done
		;;
	-cat)
		cat "$FIXTURE_ROOT/$3"
		;;
	*) exit 2 ;;
esac
EOF
chmod 0755 "$MOCK/file" "$MOCK/unsquashfs"
export FIXTURE_ROOT

required_paths='etc/companywrt/VERSION
etc/companywrt/build.conf
etc/companywrt/keys/release.pub
etc/shadow
etc/config/collectd
etc/config/firewall
etc/board.d/02_network
bin/config_generate
etc/uci-defaults/99-companywrt
usr/share/company/company-network
usr/share/company/ota-common.sh
usr/share/company/ota-check
usr/share/company/ota-apply
usr/share/company/enrollment-preflight
usr/share/company/LICENSE
usr/share/company/NOTICE
usr/share/company/CUSTOM-COMPONENTS.manifest
usr/share/company/sqm-mobile-template
usr/lib/lua/luci/view/company/dashboard.htm
www/luci-static/company/css/company.css'
printf '%s\n' "$required_paths" | while IFS= read -r path; do
	mkdir -p "$FIXTURE_ROOT/$(dirname "$path")"
	: > "$FIXTURE_ROOT/$path"
done

cp "$ROOT/VERSION" "$FIXTURE_ROOT/etc/companywrt/VERSION"
cp "$ROOT/keys/companywrt-release.pub" "$FIXTURE_ROOT/etc/companywrt/keys/release.pub"
cp "$ROOT/CUSTOM-COMPONENTS.manifest" "$FIXTURE_ROOT/usr/share/company/CUSTOM-COMPONENTS.manifest"
cat > "$FIXTURE_ROOT/etc/companywrt/build.conf" <<'EOF'
PROFILE=xiaomi_ax9000
RELEASE=25.12.5
CHANNEL=rc
EOF
cat > "$FIXTURE_ROOT/etc/shadow" <<'EOF'
root:!:20000:0:99999:7:::
daemon:*:20000:0:99999:7:::
EOF
cat > "$FIXTURE_ROOT/etc/uci-defaults/99-companywrt" <<'EOF'
uci set uhttpd.main.redirect_https='1'
/etc/init.d/collectd disable
EOF
cat > "$FIXTURE_ROOT/etc/config/collectd" <<'EOF'
config globals 'globals'
	option enable '0'
EOF
cat > "$FIXTURE_ROOT/etc/config/firewall" <<'EOF'
config zone
	option name wan
	option input REJECT
	option output ACCEPT
	option forward DROP
	list network wan
	list network wan6
config rule
	option name Allow-DHCP-Renew
config rule
	option name Allow-Ping
config rule
	option name Allow-DHCPv6
config rule
	option name Allow-ICMPv6-Input
config rule
	option name Allow-ICMPv6-Forward
EOF
cat > "$FIXTURE_ROOT/etc/board.d/02_network" <<'EOF'
xiaomi,ax9000)
	ucidef_set_interfaces_lan_wan "lan1 lan2 lan3 lan4" "wan"
EOF
cat > "$FIXTURE_ROOT/bin/config_generate" <<'EOF'
set network.loopback='interface'
set network.${1}6.device='@device'
set network.@device[-1].type='bridge'
EOF

cat > "$TMP/PACKAGE-MANIFEST" <<'EOF'
collectd - 1-r1
collectd-mod-network - 1-r1
firewall4 - 1-r1
jsonfilter - 1-r1
kmod-wireguard - 1-r1
logd - 1-r1
luci-app-pbr - 1-r1
luci-proto-wireguard - 1-r1
luci-ssl-openssl - 1-r1
pbr - 1-r1
usign - 1-r1
wireguard-tools - 1-r1
EOF

printf 'control\n' > "$ARCHIVE_ROOT/CONTROL"
printf 'kernel\n' > "$ARCHIVE_ROOT/kernel"
printf 'rootfs-placeholder\n' > "$ARCHIVE_ROOT/root"
tar -cf "$TMP/firmware.bin" -C "$TMP/archive" sysupgrade-xiaomi_ax9000

PATH="$MOCK:$PATH" UNSQUASHFS="$MOCK/unsquashfs" "$ROOT/scripts/inspect-firmware.sh" \
	--image "$TMP/firmware.bin" --package-manifest "$TMP/PACKAGE-MANIFEST" \
	--report "$TMP/locked.report" --embedded-key-id 444eb53ba66e6d45 \
	--hardware-validation NOT_PERFORMED_RC_ONLY \
	--production-gate-sha256 NONE --hardware-evidence-id NONE \
	--serial-evidence-id NONE --tested-firmware-sha256 NONE > "$TMP/locked.out"
grep -qx 'root_password_state=LOCKED' "$TMP/locked.report"
grep -qx 'default_password_embedded=NO' "$TMP/locked.report"

cat > "$FIXTURE_ROOT/etc/shadow" <<'EOF'
root::20000:0:99999:7:::
EOF
PATH="$MOCK:$PATH" UNSQUASHFS="$MOCK/unsquashfs" "$ROOT/scripts/inspect-firmware.sh" \
	--image "$TMP/firmware.bin" --package-manifest "$TMP/PACKAGE-MANIFEST" \
	--report "$TMP/empty.report" --embedded-key-id 444eb53ba66e6d45 \
	--hardware-validation NOT_PERFORMED_RC_ONLY \
	--production-gate-sha256 NONE --hardware-evidence-id NONE \
	--serial-evidence-id NONE --tested-firmware-sha256 NONE > "$TMP/empty.out"
grep -qx 'root_password_state=EMPTY' "$TMP/empty.report"

IMAGE_SHA=$(sha256sum "$TMP/firmware.bin" | awk '{print $1}')
PATH="$MOCK:$PATH" UNSQUASHFS="$MOCK/unsquashfs" "$ROOT/scripts/inspect-firmware.sh" \
	--image "$TMP/firmware.bin" --package-manifest "$TMP/PACKAGE-MANIFEST" \
	--report "$TMP/stable.report" --embedded-key-id 444eb53ba66e6d45 \
	--hardware-validation VERIFIED \
	--production-gate-sha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
	--hardware-evidence-id hw-record-fixture-001 \
	--serial-evidence-id serial-record-redacted-001 \
	--tested-firmware-sha256 "$IMAGE_SHA" > "$TMP/stable.out"
grep -qx 'hardware_validation=VERIFIED' "$TMP/stable.report"
grep -qx 'production_gate_sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' "$TMP/stable.report"
grep -qx 'hardware_evidence_id=hw-record-fixture-001' "$TMP/stable.report"
grep -qx "tested_firmware_sha256=$IMAGE_SHA" "$TMP/stable.report"

cat > "$FIXTURE_ROOT/etc/shadow" <<'EOF'
root:$6$fixture$preconfigured-hash:20000:0:99999:7:::
EOF
if PATH="$MOCK:$PATH" UNSQUASHFS="$MOCK/unsquashfs" "$ROOT/scripts/inspect-firmware.sh" \
	--image "$TMP/firmware.bin" --package-manifest "$TMP/PACKAGE-MANIFEST" \
	--report "$TMP/hash.report" --embedded-key-id 444eb53ba66e6d45 \
	--hardware-validation NOT_PERFORMED_RC_ONLY \
	--production-gate-sha256 NONE --hardware-evidence-id NONE \
	--serial-evidence-id NONE --tested-firmware-sha256 NONE > "$TMP/hash.out" 2> "$TMP/hash.err"; then
	echo 'preconfigured root password hash unexpectedly passed firmware inspection' >&2
	exit 1
fi
grep -q 'preconfigured root password hash' "$TMP/hash.err"
if grep -q 'fixture' "$TMP/hash.err"; then
	echo 'firmware inspector leaked a root password hash' >&2
	exit 1
fi

cat > "$FIXTURE_ROOT/etc/shadow" <<'EOF'
root:!$6$fixture$locked-but-preconfigured-hash:20000:0:99999:7:::
EOF
if PATH="$MOCK:$PATH" UNSQUASHFS="$MOCK/unsquashfs" "$ROOT/scripts/inspect-firmware.sh" \
	--image "$TMP/firmware.bin" --package-manifest "$TMP/PACKAGE-MANIFEST" \
	--report "$TMP/locked-hash.report" --embedded-key-id 444eb53ba66e6d45 \
	--hardware-validation NOT_PERFORMED_RC_ONLY \
	--production-gate-sha256 NONE --hardware-evidence-id NONE \
	--serial-evidence-id NONE --tested-firmware-sha256 NONE > "$TMP/locked-hash.out" 2> "$TMP/locked-hash.err"; then
	echo 'locked preconfigured root password hash unexpectedly passed firmware inspection' >&2
	exit 1
fi
grep -q 'preconfigured root password hash' "$TMP/locked-hash.err"

echo 'firmware rootfs shadow EMPTY/LOCKED acceptance and preset-hash rejection: ok'
