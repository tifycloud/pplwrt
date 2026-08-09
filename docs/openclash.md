# OpenClash：官方依赖与冲突边界

官方 OpenClash README 与 `luci-app-openclash/Makefile`：

- README：<https://github.com/vernesong/OpenClash/blob/master/README.md>
- Makefile：<https://raw.githubusercontent.com/vernesong/OpenClash/master/luci-app-openclash/Makefile>
- 用户指南：<https://github.com/vernesong/OpenClash/blob/dev/.github/skills/openclash-user-guide/SKILL.md>

官方 README 列出的依赖包括 `luci`、`luci-base`、`dnsmasq-full`、`bash`、`curl`、`ca-bundle`、`ipset`、`ip-full`、`ruby`、`ruby-yaml`、`unzip`、`kmod-tun`、`kmod-inet-diag`、`luci-compat`，以及旧 iptables 路径的 `iptables`/`kmod-ipt-nat`/`iptables-mod-tproxy`/`iptables-mod-extra`/`ip6tables-mod-nat` 和 firewall4 路径的 `kmod-nft-tproxy`。

本项目使用 OpenWrt 25.12.5 的 apk + firewall4/nftables。RC4 基础镜像只保留路由器本身
需要的 `curl`、`ca-bundle`、`ip-full` 和 `dnsmasq-full`；Ruby、bash、unzip、Lua compatibility、
TUN/tproxy 等 OpenClash 专用运行依赖不再预装。管理员选定 OpenClash 版本、模式和回滚窗口后，
再由 apk 解析完整依赖；LuCI 本体、Mihomo、规则与订阅始终独立管理。

安装 OpenClash 前记录：

1. 选择 TUN 或 nftables tproxy 其中一种主数据路径。
2. 记录 DNS 劫持、监听地址、fwmark、路由表和 nft chain owner。
3. 关闭重复 PBR policy，或让 PBR 只处理未被 OpenClash 接管的源/目的/端口。
4. 在断电/回滚窗口测试国内直连、代理域名、IPv4/IPv6、WAN 故障和 LuCI 恢复。

OpenClash 的 release/核心/订阅由管理员按官方页面独立确认，任何自动更新都不能越过 OTA 人工确认。
