# 双 WAN、PBR 与只读变更计划

固定业务角色：

| UCI interface | 线路 | 规划用途 | route metric |
| --- | --- | --- | --- |
| `unicom` | 联通 1 Gbit/s | office 默认出口 | 10 |
| `mobile` | 移动 100 Mbit/s | server/指定 employee/稳定上传 | 20 |

物理 DSA 设备名必须在真机通过 `ip -br link`/LuCI 确认，不能复制示例。生成器严格拒绝
非法接口、IPv4/CIDR、网关、重复 WAN、域名/端口注入；IPv6 不由此计划重写，现有
loopback、DSA、默认 WAN/WAN6、firewall defaults 和 fw4 默认规则全部保留。

```sh
company-network plan \
  --unicom-device wan \
  --mobile-device lan4 \
  --office-cidr 192.168.50.0/24 \
  --server 192.168.50.10 \
  --employee 192.168.50.20/32 \
  --mobile-dest uploads.example.com \
  --mobile-port tcp:443 \
  --output /tmp/company-network-plan
less /tmp/company-network-plan/uci.batch /tmp/company-network-plan/REVIEW.md
```

输出只使用 `set network.unicom/mobile`、命名 firewall zone/forwarding 和命名 PBR
policy；没有 package-wide import/delete、commit 或 reload。具体源、目标域名/IPv4/CIDR、
TCP/UDP 端口可分别选择 mobile/unicom，最后一条 office 默认 policy 指向 unicom。
生成器会先规范化 domain 大小写、IPv4 与 `/32`、CIDR host bits、`443-443` 与单端口，
并检查 CIDR/port range 重叠；同一或重叠 destination/port 不能同时分配给 mobile 和
unicom，同一 role 内的重复/重叠项也会被拒绝，避免依赖 UCI 顺序产生歧义。
域名策略要求 `dnsmasq.nftset`，由预装 `dnsmasq-full`/pbr 支持。

## 人工应用门禁

项目无法对未知 DSA/上游/boot 环境实现可靠自动回滚，因此 **没有 apply 命令**。
管理员必须在隔离有线 LAN、带 out-of-band/厂商恢复能力的维护窗口：

1. 导出 network/firewall/pbr，记录 WAN6、nft ruleset、ip rule/table、OpenClash marks；
2. 逐行审阅 `uci.batch`，确认命名 section 无冲突；
3. 只 staging：`uci -q batch < uci.batch`，审查 `uci changes`；错误则 `uci revert`；
4. 人工决定 commit/reload，先确认 HTTPS 管理仍可用；
5. 分别测试两条 WAN、WAN 入站拒绝、IPv4/IPv6、DNS、源/域名/地址/端口命中、
   会话保持/故障和 OpenClash 唯一规则所有者。

基础镜像不安装 mwan3。PBR/OpenClash/手工 nft 不得共享 mark/table/chain 所有权。
