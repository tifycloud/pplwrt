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
grep -q 'mobile' "$ROOT/configs/overlay/usr/share/company/sqm-mobile-template"
grep -q 'disabled on `unicom`' "$ROOT/configs/overlay/usr/share/company/sqm-mobile-template"
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
grep -q 'current ImageBuilder pipeline does not compile or install them as APKs' "$ROOT/NOTICE"
grep -Fq 'THE SOFTWARE IS PROVIDED "AS IS"' "$ROOT/LICENSE"
grep -Fq 'packages/$package/root' "$ROOT/scripts/build-imagebuilder.sh"
grep -q 'keys/companywrt-release.pub' "$ROOT/scripts/build-imagebuilder.sh"
grep -q 'inspect-firmware.sh' "$ROOT/scripts/build-imagebuilder.sh"
grep -Fq 'profiles.json must identify exactly one squashfs sysupgrade image' "$ROOT/scripts/build-imagebuilder.sh"
grep -Fq 'host Finder metadata leaked into the firmware rootfs' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'loopback_dsa_wan6_generation=PRESERVED' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'default_firewall_rules=PRESERVED' "$ROOT/scripts/inspect-firmware.sh"
grep -Fq 'refusing to bind a dirty worktree to a release source commit' "$ROOT/scripts/build-imagebuilder.sh"
grep -Fq 'ignored files exist in firmware input directories' "$ROOT/scripts/build-in-container.sh"

[ -s "$ROOT/keys/companywrt-release.pub" ]
if git -C "$ROOT" ls-files | grep -Eiq '(private|secret).*\.(key|sec)$|(^|/)secret\.key$'; then
	echo 'private signing key appears tracked' >&2
	exit 1
fi
echo 'package capability, overlay inventory/SBOM/NOTICE and firmware inspection sources: ok'
