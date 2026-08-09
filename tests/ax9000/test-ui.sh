#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
DASHBOARD="$ROOT/packages/luci-app-company/root/www/luci-static/resources/view/company/dashboard.js"
SETUP="$ROOT/packages/luci-app-company/root/www/luci-static/resources/view/company/setup.js"
THEME="$ROOT/packages/luci-theme-company/root/www/luci-static/company/cascade.css"
HEADER="$ROOT/packages/luci-theme-company/root/usr/share/ucode/luci/template/themes/company/header.ut"
MENU="$ROOT/packages/luci-app-company/root/usr/share/luci/menu.d/luci-app-company.json"
ACL="$ROOT/packages/luci-app-company/root/usr/share/rpcd/acl.d/luci-app-company.json"

for file in "$DASHBOARD" "$SETUP" "$THEME" "$HEADER" "$MENU" "$ACL"; do
	[ -s "$file" ] || { echo "missing CompanyWrt UI file: $file" >&2; exit 1; }
done

for marker in 'memory.available' 'getDHCPLeases' '设置宽带账号' '重新运行设置向导' 'OpenClash.*未预装' 'network.interface'; do
	grep -Eq "$marker" "$DASHBOARD"
done
for marker in 'setPassword' "uci.set('network', 'wan', 'proto'" 'cw-pppoe-user' 'cw-pppoe-pass' 'sae-mixed' "setup_complete', '1'" '管理员密码至少需要 10 个字符'; do
	grep -Fq "$marker" "$SETUP"
done
for marker in '@media (max-width: 900px)' 'prefers-reduced-motion' '.cw-wizard' '.cw-grid' '.cw-password-warning' '#mainmenu' '#maincontent'; do
	grep -Fq "$marker" "$THEME"
done
grep -Fq "@import url('/luci-static/openwrt2020/cascade.css')" "$THEME"
grep -Fq 'CompanyWrt 企业路由器管理中心' "$HEADER"
grep -Fq 'themes/company' "$ROOT/packages/luci-theme-company/Makefile"
grep -Fq 'luci-static/company' "$ROOT/packages/luci-theme-company/root/etc/uci-defaults/30_luci-theme-company"
grep -Fq '"path": "company/setup"' "$MENU"
grep -Fq '"luci": ["setPassword"]' "$ACL"
grep -Fq '"uci": ["company", "network", "wireless", "luci"]' "$ACL"

if grep -Fq '+luci-compat' "$ROOT/packages/luci-app-company/Makefile"; then
	echo 'modern CompanyWrt app must not require the legacy LuCI compatibility runtime' >&2
	exit 1
fi
if find "$ROOT/packages/luci-app-company/root/usr/lib/lua" -type f -print -quit 2>/dev/null | grep -q .; then
	echo 'legacy Lua view remains in CompanyWrt app' >&2
	exit 1
fi
if grep -Eq '设备健康|基线通过|PBR 已就绪' "$DASHBOARD"; then
	echo 'dashboard contains an unverified readiness claim' >&2
	exit 1
fi
echo 'CompanyWrt full theme, reclaim-aware dashboard and guided PPPoE/Wi-Fi/password setup: ok'
