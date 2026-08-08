# CompanyWrt UI

`luci-app-company-overlay` 提供只读 dashboard，`luci-theme-company-overlay` 提供局部、
响应式、深色/减少动画/键盘可访问 CSS。它们由 ImageBuilder FILES overlay 安装，
当前不是 APK；实际路径与内容由固件解包测试核验。

页面读取 `/etc/companywrt/VERSION`、build.conf、company/pbr/firewall/uhttpd UCI：

- PBR 只显示“配置已启用”或“未启用/未安装”，并明确运行/命中未验证；
- WAN firewall、NAT、HTTPS 都标为 **UCI 配置快照**，不推断实际 nft/cert 健康；
- 无线显示配置值，但监管域/BDF/HE80/HE160 表现仍待真机；
- 顶部始终显示候选配置/未验收，不再静态声称“设备健康/PBR 已就绪/基线通过”。

UI 不显示凭据、订阅、私钥或日志正文，也没有一键网络 apply/OTA。管理员从官方 LuCI
页面或审阅后的 CLI 流程操作。全局主题保持官方 openwrt2020；自定义 CSS/页面损坏时
仍可使用官方救援入口。
