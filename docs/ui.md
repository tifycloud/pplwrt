# CompanyWrt UI

`luci-theme-company` 提供可访问 CSS，`luci-app-company` 提供可运行的只读 dashboard：显示设备/release/HE80、WAN/PBR/OpenClash 边界，并链接到官方 LuCI 接口、防火墙、PBR、备份和刷写页。它不修改全局 LuCI 模板，官方 openwrt/openwrt-2020 主题始终作为救援主题。

UI 不显示密码、订阅、日志正文或私钥，也不提供一键 OTA/一键网络覆盖按钮。现场操作必须回到 CLI/官方 LuCI 变更流程、备份和管理员确认；这使 dashboard 损坏时不会阻止救援。
