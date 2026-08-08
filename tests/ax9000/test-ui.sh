#!/bin/sh
set -eu
ROOT=$(cd -P -- "$(dirname "$0")/../.." && pwd)
VIEW="$ROOT/packages/luci-app-company/root/usr/lib/lua/luci/view/company/dashboard.htm"
CSS="$ROOT/packages/luci-theme-company/root/www/luci-static/company/css/company.css"
for marker in company-kpis company-flow company-admin-strip company-pill company-footer company-skip-link; do
  grep -q "$marker" "$VIEW"
done
for marker in '@media (max-width: 780px)' 'prefers-reduced-motion' 'prefers-color-scheme: dark' '.company-card-wide'; do
  grep -q "$marker" "$CSS"
done
grep -q 'luci-static/company/css/company.css' "$VIEW"
grep -q '<main id="company-content"' "$VIEW"
grep -q 'HE160' "$VIEW"
grep -q 'uci:foreach("firewall", "zone"' "$VIEW"
grep -q 'uci:get("pbr", "config", "enabled")' "$VIEW"
grep -q 'uhttpd.*redirect_https' "$VIEW"
grep -q '候选配置 · 未验收' "$VIEW"
grep -q '仅从 UCI 读取' "$VIEW"
grep -Fq '+luci-compat' "$ROOT/packages/luci-app-company/Makefile"
grep -Fq '/usr/lib/lua/luci/view/company' "$ROOT/packages/luci-app-company/Makefile"
if find "$ROOT/packages/luci-app-company/root/usr/share/lua" -type f -print -quit 2>/dev/null | grep -q .; then
	echo 'LuCI overlay still contains files in the non-runtime /usr/share/lua path' >&2
	exit 1
fi
[ ! -e "$ROOT/packages/luci-app-company/root/etc/init.d/company" ]
for false_claim in '设备健康' '可管理' '有线管理面已就绪' 'PBR 已就绪' '基线通过' '稳定基线'; do
  if grep -Fq "$false_claim" "$VIEW"; then
    echo "static readiness claim remains in dashboard: $false_claim" >&2
    exit 1
  fi
done
grep -q 'company-pill-neutral' "$CSS"
echo 'CompanyWrt UI dynamic configuration snapshot and unverified-state markers: ok'
