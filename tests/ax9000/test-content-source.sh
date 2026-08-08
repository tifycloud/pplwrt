#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)

for package in usign jsonfilter kmod-wireguard wireguard-tools luci-proto-wireguard logd collectd collectd-mod-network; do
	grep -qx "$package" "$ROOT/configs/ax9000/packages.txt" || { echo "missing base package: $package" >&2; exit 1; }
done
for package in sqm-scripts luci-app-sqm; do
	grep -qx "$package" "$ROOT/configs/ax9000/packages-sqm-optional.txt"
	if grep -qx "$package" "$ROOT/configs/ax9000/packages.txt"; then
		echo "optional SQM package leaked into base: $package" >&2
		exit 1
	fi
done
for package in luci-app-openclash openclash mihomo; do
	if grep -qx "$package" "$ROOT/configs/ax9000/packages.txt"; then
		echo "OpenClash/Mihomo payload leaked into base: $package" >&2
		exit 1
	fi
done
grep -q 'mobile' "$ROOT/configs/overlay/usr/share/company/sqm-mobile-template"
grep -Fq "disabled on \`unicom\`" "$ROOT/configs/overlay/usr/share/company/sqm-mobile-template"
grep -q 'Plain syslog has no confidentiality' "$ROOT/configs/overlay/usr/share/company/log-forwarding-template"
grep -q '/etc/init.d/collectd disable' "$ROOT/configs/overlay/etc/uci-defaults/99-companywrt"
if grep -Eq "option enable '[^0]'|config network_(listen|server)" "$ROOT/configs/overlay/etc/config/collectd"; then
	echo 'collectd overlay is not dormant by default' >&2
	exit 1
fi

for component in luci-app-company-overlay luci-theme-company-overlay companywrt-device-overlay companywrt-operations-scripts; do
	grep -Fq "$component" "$ROOT/CUSTOM-COMPONENTS.manifest"
	grep -Fq "$component" "$ROOT/scripts/inspect-firmware.sh"
done
grep -q 'overlay-not-apk' "$ROOT/scripts/augment-sbom.py"
grep -q 'companywrt:package-manifest-name' "$ROOT/scripts/augment-sbom.py"
grep -q 'NOASSERTION' "$ROOT/scripts/augment-sbom.py"
grep -q -- '--package-manifest' "$ROOT/scripts/build-buildroot.sh"
grep -q 'current Buildroot pipeline does not compile or install them as APKs' "$ROOT/NOTICE"
grep -Fq 'THE SOFTWARE IS PROVIDED "AS IS"' "$ROOT/LICENSE"
grep -Fq "packages/\$package/root" "$ROOT/scripts/build-buildroot.sh"
grep -q 'CURRENT_PUBLIC_KEY' "$ROOT/scripts/build-buildroot.sh"
grep -q 'inspect-firmware.sh' "$ROOT/scripts/build-buildroot.sh"
grep -Fq "Buildroot must produce exactly one host \$tool_name inspector binary" "$ROOT/scripts/build-buildroot.sh"
grep -Fq "resolve_single_inspector_tool dumpimage '*/host/u-boot-*/tools/dumpimage'" "$ROOT/scripts/build-buildroot.sh"
grep -Fq "resolve_single_inspector_tool dtc '*/linux-*/scripts/dtc/dtc'" "$ROOT/scripts/build-buildroot.sh"
grep -Fq "resolve_single_inspector_tool unsquashfs '*/host/squashfs4-*/squashfs-tools/unsquashfs'" "$ROOT/scripts/build-buildroot.sh"
grep -Fq 'profiles.json must identify exactly one squashfs sysupgrade image' "$ROOT/scripts/build-buildroot.sh"
grep -Fq 'full-openwrt-buildroot' "$ROOT/scripts/build-buildroot.sh"
grep -Fq '0001-qualcommax-add-ax9000-darkyun-large-ubi.patch' "$ROOT/scripts/build-buildroot.sh"
grep -Fq 'host Finder metadata leaked into the firmware rootfs' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'rootfs contains a preconfigured root password hash' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'root_password_state=' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'loopback_dsa_wan6_generation=PRESERVED' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'default_firewall_rules=PRESERVED' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'openclash_preinstalled=NO' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'refusing to bind a dirty worktree to a release source commit' "$ROOT/scripts/build-buildroot.sh"
grep -Fq 'ignored files exist in firmware input directories' "$ROOT/scripts/build-in-container.sh"

[ -s "$ROOT/keys/companywrt-release.pub" ]
[ -s "$ROOT/keys/companywrt-release-previous.pub" ]
grep -qx 'CURRENT_KEY_ID=444eb53ba66e6d45' "$ROOT/keys/ROTATION.env"
grep -qx 'PREVIOUS_KEY_ID=679439846de7ada5' "$ROOT/keys/ROTATION.env"
grep -Fq 'PUBLIC_KEY=/etc/companywrt/keys/release.pub' "$ROOT/scripts/ota-apply.sh"
grep -Fq -- '--public-key is forbidden in production' "$ROOT/scripts/ota-apply.sh"
if git -C "$ROOT" ls-files | grep -Eiq '(private|secret).*\.(key|sec)$|(^|/)secret\.key$'; then
	echo 'private signing key appears tracked' >&2
	exit 1
fi
echo 'package capability, overlay inventory/SBOM/NOTICE and firmware inspection sources: ok'
