# luci-theme-company-overlay

CompanyWrt 的轻量可访问视觉 overlay。当前 Buildroot `files/` 直接复制 root tree，并未构建
APK；release manifest/SBOM/NOTICE 因此使用 `-overlay` 名称。它不替换官方救援主题，
管理员在 CSS/应用损坏时仍可回到 `luci-theme-openwrt`/openwrt2020。dashboard 显式加载
样式表，不修改全局 LuCI 模板。
