# 首次配置清单

首次启动请使用有线 LAN，立即修改 root/管理员凭据并保存密码管理器中的随机值；关闭 WAN 管理、确认 HTTPS 证书和 SSH 只允许管理网段。

按顺序完成：

1. `ubus call system board` 确认 board/profile；`cat /etc/companywrt/build.conf` 确认 release。
2. 在 LuCI 设定时区/NTP、语言 zh_cn、管理 IP 和官方救援主题；保留 CompanyWrt dashboard 作为只读入口。
3. 逐个确认 WAN 设备名、MTU、DHCP/PPPoE/VLAN，不要把示例 `eth0.2/eth0.3` 直接当成事实。
4. 先只启用 WAN1；完成 DNS、IPv4/IPv6、内外网访问测试后再接 WAN2。
5. 按 [dual-wan-pbr.md](dual-wan-pbr.md) 生成配置，审阅后再应用；记录 fwmark/table 与 OpenClash 冲突检查。
6. 最后做配置/日志备份、恢复演练和升级确认。未完成备份不得开启自动升级。
