# AX9000 测试矩阵

| 영역 | stable 必测 | beta/专项 |
| --- | --- | --- |
| 启动/刷写 | factory、initramfs、sysupgrade 校验；断电后可救援 | 分区/DTS 变更 |
| LuCI | HTTPS、zh_cn、官方救援主题、CompanyWrt dashboard | 浏览器兼容/无 JS 降级 |
| 网络 | LAN DHCP/DNS、WAN1/WAN2 DHCP/PPPoE、NAT、IPv4/IPv6 | VLAN trunk、WireGuard |
| PBR | 源/目的/端口策略、fwmark/ip rule、WAN 故障、连接保持 | 与 OpenClash 规则交叉 |
| 防火墙 | fw4/nftables 默认拒绝、日志、回滚 | 自定义 nft chain |
| 无线 | 2.4/5 GHz HE80、监管域、漫游、吞吐、重启恢复 | HE160、BDF workaround、DFS |
| OpenClash | 依赖安装、TUN/tproxy 单一路径、DNS、停用恢复 | 核心/订阅更新 |
| OTA | manifest/SHA、管理员确认、配置/日志恢复 | 分阶段/回滚 |

每项记录硬件序列号、固件 git commit、测试时间、监管域、客户端、接口名、日志摘要和通过/失败证据；不得把包含凭据的原始日志提交仓库。
