#!/bin/sh
set -eu
ROOT=$(cd -P -- "$(dirname "$0")/../.." && pwd)
VIEW="$ROOT/packages/luci-app-company/root/usr/share/lua/luci/view/company/dashboard.htm"
CSS="$ROOT/packages/luci-theme-company/root/www/luci-static/company/css/company.css"
for marker in company-kpis company-flow company-admin-strip company-pill company-footer; do
  grep -q "$marker" "$VIEW"
done
for marker in '@media (max-width: 780px)' 'prefers-reduced-motion' 'prefers-color-scheme: dark' '.company-card-wide'; do
  grep -q "$marker" "$CSS"
done
grep -q 'luci-static/company/css/company.css' "$VIEW"
grep -q 'HE160' "$VIEW"
echo 'CompanyWrt UI structure and responsive/accessibility markers: ok'
