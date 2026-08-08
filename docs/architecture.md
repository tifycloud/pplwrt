# 架构与长期边界

CompanyWrt 分为四层：

1. **官方固件层**：OpenWrt 25.12.5 stable、`qualcommax/ipq807x`、官方 `xiaomi_ax9000` profile、标准分区、`firewall4`/nftables、LuCI+luci-ssl+简体中文+官方救援主题。
2. **策略层**：`pbr` 生成 fwmark、路由表和 nftables 规则；双 WAN 按连接/源/目的/端口选择，不在基础版引入 `mwan3`。
3. **可选服务层**：VLAN、WireGuard、SQM、监控、OpenClash。每个服务都有明确的 mark、DNS、MTU 和回滚记录；未启用时不写入镜像。
4. **运维层**：CompanyWrt LuCI dashboard、备份、OTA 检查、manifest/SHA256 和 CI release。订阅、私钥、日志备份不入 git。

### 为什么先 ImageBuilder

ImageBuilder 只重组官方 target 包，构建快、差异小、可复现。若未来需要修改 DTS、分区、内核选项或 BDF 固件，先提交设计与救援测试，再切换到固定 OpenWrt 源码/Buildroot 构建；不得用 ImageBuilder 伪装硬件修改。

### 数据流和冲突约束

LAN 流量先经过 fw4 基础防火墙，然后由 PBR 根据源/目的/端口设置 mark 和路由表；连接跟踪保证同一连接不漂移。OpenClash 如果接管流量，必须选择 TUN 或 nftables tproxy 的单一路径，并明确 DNS/mark 所有者。不得让 OpenClash、PBR 和手工 nft 同时写同一个 mark/table/chain。

### AX9000 无线

官方 profile 包含 AX9000 专用 ipq-wifi、ath11k/ath10k 固件。默认 HE80。HE160 受监管域、客户端、驱动和 BDF 影响，采用独立 overlay 与测试记录，不把 workaround 混入稳定基础配置。
