# 双 WAN、PBR 与 nftables

CompanyWrt 把双 WAN 当成策略路由，而不是无条件的 per-packet 负载均衡。`pbr` 写入 fwmark 和独立路由表，`firewall4`/nftables 负责过滤、NAT 和状态；基础镜像不安装 `mwan3`，避免两个故障检测/标记系统争夺连接所有权。

## 推荐流程

```sh
company-network generate --wan1 eth0.2 --wan2 eth0.3 \
  --lan-cidr 192.168.50.1/24 --output /tmp/company-network
less /tmp/company-network/network /tmp/company-network/firewall /tmp/company-network/pbr
company-network apply --wan1 eth0.2 --wan2 eth0.3 --yes
```

先在隔离窗口验证。生成器不接受 PPPoE 密码，不猜接口，不会自动把连接分散到两个链路；`--yes` 才会写 UCI，并在变更前留下可回滚备份。

## 策略建模

- 连接/源地址：办公 VLAN 固定 WAN1，访客 VLAN 固定 WAN2。
- 目的地址：企业 SaaS、VPN 对端或特定 CDN 使用明确的目的集合。
- 端口：只为有清晰需求的 TCP/UDP 端口添加规则；DNS、DHCP、已建立连接先排除。
- 故障：用链路探测和管理员确认切换，记录切换时间与连接中断范围。

任何规则都要写出 `fwmark -> table -> interface` 映射。建立 OpenClash 后先选择是否让它接管该流量；若接管，禁用相应 PBR 规则，反之亦然。验证 `nft list ruleset`、`ip rule`、`ip route show table all` 和连接跟踪，确认没有重复 chain/mark。
