#!/bin/sh
set -eu
ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
DASHBOARD="$ROOT/packages/luci-app-company/root/www/luci-static/resources/view/company/dashboard.js"
SETUP="$ROOT/packages/luci-app-company/root/www/luci-static/resources/view/company/setup.js"
SETUP_RENDER_TEST="$ROOT/tests/ax9000/setup-render.test.js"
THEME="$ROOT/packages/luci-theme-liquid/htdocs/luci-static/liquid/cascade.css"
THEME_JS="$ROOT/packages/luci-theme-liquid/htdocs/luci-static/liquid/main.js"
HEADER="$ROOT/packages/luci-theme-liquid/ucode/template/themes/liquid/header.ut"
FOOTER="$ROOT/packages/luci-theme-liquid/ucode/template/themes/liquid/footer.ut"
SYSAUTH="$ROOT/packages/luci-theme-liquid/ucode/template/themes/liquid/sysauth.ut"
THEME_ACL="$ROOT/packages/luci-theme-liquid/root/usr/share/rpcd/acl.d/luci-theme-liquid.json"
THEME_DEFAULTS="$ROOT/packages/luci-theme-liquid/root/etc/uci-defaults/30_luci-theme-liquid"
THEME_RPC="$ROOT/packages/luci-theme-liquid/root/usr/share/rpcd/ucode/luci-theme-liquid"
UPSTREAM="$ROOT/packages/luci-theme-liquid/UPSTREAM.md"
MENU="$ROOT/packages/luci-app-company/root/usr/share/luci/menu.d/luci-app-company.json"
ACL="$ROOT/packages/luci-app-company/root/usr/share/rpcd/acl.d/luci-app-company.json"

for file in "$DASHBOARD" "$SETUP" "$SETUP_RENDER_TEST" "$THEME" "$THEME_JS" "$HEADER" "$FOOTER" "$SYSAUTH" \
	"$THEME_ACL" "$THEME_DEFAULTS" "$THEME_RPC" "$UPSTREAM" "$MENU" "$ACL"; do
	[ -s "$file" ] || { echo "missing Liquid/CompanyWrt UI file: $file" >&2; exit 1; }
done

node "$SETUP_RENDER_TEST" "$SETUP"

for marker in 'memory.available' 'getDHCPLeases' '宽带与首次设置' '设置宽带和 Wi' 'OpenClash.*未预装' 'network.interface' '胖胖龙专用路由器'; do
	grep -Eq "$marker" "$DASHBOARD"
done
for marker in 'setPassword' "uci.set('network', 'wan', 'proto'" 'cw-pppoe-user' 'cw-pppoe-pass' 'sae-mixed' "setup_complete', '1'" '管理员密码至少需要 10 个字符' '胖胖龙专用路由器'; do
	grep -Fq "$marker" "$SETUP"
done
for marker in '@media screen and (max-width: 854px)' 'prefers-reduced-motion' '.cw-wizard' '.cw-grid' '#mainmenu' '#maincontent' '.ppl-brand' '.cw-console-head' '.cw-memory-strip' '.cbi-progressbar::after' 'content: attr(title)'; do
	grep -Fq "$marker" "$THEME"
done
for marker in 'availablePercent' 'usedPercent' '实际占用' '可用内存' '按 MemAvailable 计算' '宽带与首次设置'; do
	grep -Fq "$marker" "$DASHBOARD"
done
for marker in '胖胖龙专用路由器' 'data-liquid-mode' 'data-liquid-accent' 'cascade.css'; do
	grep -Fq "$marker" "$HEADER"
done
grep -Fq '胖胖龙专用路由器' "$FOOTER"
grep -Fq "include('header', { blank_page: true })" "$SYSAUTH"
grep -Fq 'luci-theme-liquid' "$ROOT/packages/luci-theme-liquid/Makefile"
grep -Fq 'ad0cce67c02ce9ce0154c2f08491fc8ac1daf06b' "$UPSTREAM"
grep -Fq 'luci-static/liquid' "$THEME_DEFAULTS"
grep -Fq "L.require('rpc')" "$THEME_JS"
grep -Fq "object: 'luci-theme-liquid'" "$THEME_JS"
grep -Fq "return { 'luci-theme-liquid': methods }" "$THEME_RPC"
grep -Fq "match(custom, /^#[0-9a-fA-F]{6}$/)" "$THEME_RPC"
grep -Fq '"path": "company/setup"' "$MENU"
grep -Fq '"luci": ["setPassword"]' "$ACL"
grep -Fq '"uci": ["company", "network", "wireless", "luci", "liquid"]' "$ACL"
grep -Fq '"luci-theme-liquid": ["setPreferences"]' "$THEME_ACL"

if grep -En 'www\.bing\.com|wget|system\(|bing-wallpaper|/www/liquid-cache' "$HEADER" "$FOOTER" "$THEME_JS" "$THEME"; then
	echo 'runtime Liquid files still contain external wallpaper or shell execution logic' >&2
	exit 1
fi
for removed in \
	"$ROOT/packages/luci-theme-liquid/root/usr/share/ucode/luci/controller/liquid.uc" \
	"$ROOT/packages/luci-theme-liquid/root/usr/share/luci/menu.d/liquid.json"; do
	[ ! -e "$removed" ] || { echo "deprecated Liquid controller remains: $removed" >&2; exit 1; }
done
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

echo 'Pinned Liquid theme, product branding, safe preferences, dashboard and first-run wizard: ok'
