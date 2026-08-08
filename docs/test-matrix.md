# AX9000 RC 与生产门禁矩阵

源码测试、Linux/amd64 构建、squashfs 内容核查和 CI attestation 只允许产出 RC/beta；
不能替代真机。正式 stable 必须把 `production-gates/TEMPLATE.env` 复制为
`production-gates/<VERSION>.env`，填入脱敏证据 hash、命名审批人和 UTC 时间，所有门禁
PASS。模板/占位符/缺项会被 CI 拒绝。

| 门禁 | RC 自动证据 | stable 真机证据 |
| --- | --- | --- |
| 身份/启动 | manifest profile/board；sysupgrade tar/squashfs | 硬件变体、secure boot 实测、board、MTD、active/fallback slot |
| 救援 | 官方主题/文档存在 | 厂商恢复或串口成功；错误镜像拒绝；救援耗时 |
| 断电 | 无 | 刷写/启动关键阶段演练与恢复 PASS（受控测试） |
| 管理面 | HTTPS redirect 与 preflight 内容检查 | 隔离有线首登、证书、SSH、WAN 扫描、救援主题 PASS |
| 无线 | HE80 配置值、HE160 未声明 | 2.4/5 GHz HE80、监管域/BDF、重启；HE160 仅专项 |
| 双 WAN | plan-only 与注入测试 | unicom 1G、mobile 100M、故障/会话/上传/入站拒绝 |
| IPv6 | 保留 WAN6、无 destructive import | PD/DNS/firewall/PBR/OpenClash 回归 |
| VLAN | 模板/包边界 | DSA trunk/access/隔离/管理可达/回滚 |
| WireGuard | kmod/tools/LuCI 进入 manifest/rootfs | handshake、AllowedIPs/MTU/PBR/密钥恢复 |
| PBR | 源/域名/IP/端口 plan 与默认 unicom | nft/ip rule/table 命中、冲突/故障/连接保持 |
| OpenClash | 仅依赖、本体不在 SBOM | 安装来源、TUN/tproxy 单所有者、DNS、停用恢复 |
| 日志/监控 | logd/collectd 基础；plugin/init 默认禁用且无 endpoint | 脱敏、隔离/WG transport、保留/告警/带宽 |
| SQM | mobile 可选模板；base 不含 | mobile CPU/吞吐/延迟；unicom 默认关闭 |
| OTA | usign/HTTPS/SIZE/SHA/board/双确认/`-T` | 备份、slot、升级/配置恢复/失败救援 |

真机记录包含固件 SHA/commit、测试时间、管理员、完整硬件/区域变体（证据公开时脱敏）、
客户端/监管域、通过/失败摘要与证据包 SHA。不得提交 serial、MAC、公网 IP、凭据、密钥、
订阅或原始日志。
