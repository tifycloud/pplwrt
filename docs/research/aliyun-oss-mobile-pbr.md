# AX9000 双 WAN 的上传优先移动 MVP

研究日期：2026-08-10。目标是 CompanyWrt/OpenWrt 25.12.5、Xiaomi AX9000 上只实现三类已确认流量：

- 本地 Argo CD（controller/repo-server）访问 ACK kubeconfig 中的 Kubernetes API endpoint；
- ACK 节点（固定出站 EIP）访问本地 Harbor，拉取请求由 ACK 发起、镜像层响应返回本地 ACK；
- 本地专用 uploader 向 OSS bucket endpoint 上传镜像/文件。

中国移动静态公网 `/27` 只承载这些业务；联通 PPPoE 保持主路由，因此未匹配流量（普通浏览、下载等）走联通。本文是研究和只读验证计划，不执行路由器、Harbor、ACK、OSS 或其他外部系统变更。地址、接口、端口、证书和密钥都是现场变量。

## 结论先行

### MVP 建议（工程推论）

1. 只建三条 pbr policy：
   - `argo -> ACK API`：Argo 主机/网段作为源，使用 kubeconfig `server` 的精确 FQDN/IP 和端口作为目的，出口 `mobile`；
   - `uploader -> OSS`：专用 uploader 源地址，使用实际 bucket endpoint/CNAME 和 443 作为目的，出口 `mobile`；
   - `Harbor reply -> ACK EIP`：Harbor 内网源地址，ACK 固定 EIP 作为目的，出口 `mobile`。这条规则用于 DNAT 连接的回包，不设置目的端口，因为回包目的端口是 ACK 的临时端口。
2. 不建立 pbr catch-all；主路由表默认网关必须是联通。这样未匹配流量继续走联通，不依赖额外的“所有阿里云网段”清单。
3. 移动 WAN 只对 ACK 固定 EIP 放行 TCP 443，并将移动公网地址 443 DNAT 到 Harbor；其他移动入站保持拒绝。Harbor 主机也要做同一源地址 allowlist 和 HTTPS 校验。
4. MVP 不添加自定义 nft `ct mark` 保存/恢复、额外 netifd mark/table、mwan3、隧道或 ACR。固定 ACK EIP、固定 Harbor 内网源地址和单一 Mobile 公网地址是本简化方案成立的前提。
5. 只有验证显示 Harbor 回包仍选联通、ACK EIP 不稳定、源地址被中间 NAT 改写或 OpenClash 抢走 mark 时，才把 conntrack mark/更强隔离列为后续故障方案；本期不预先实现。

### 关键判断：简单 source+destination 是否足够

对 A/B 的本地发起连接，足够：pbr 在 LAN 主机发出的首包上按源和精确目的打标并选择 Mobile；正常 NAT/conntrack 会让响应回到 Mobile，再反向映射到本地源主机。

对 C，在以下前提均成立时也足够：

- ACK 对外可见的固定 EIP 是路由器看到的真实源地址；
- 443 DNAT 不把 ACK 源地址 SNAT 成其他地址；
- Harbor 回包先到这台路由器，回包在进入路由决策时仍呈现 `src=<HARBOR_LAN_IP>, dst=<ACK_FIXED_EIP>`；
- pbr 的 `mobile` 路由表可用，且 OpenClash 没有改写/抢占该流的 mark；
- Harbor 没有其他默认网关绕过路由器。

这是基于官方 hook/NAT 语义的工程推论，必须用抓包和 `ip rule` 现场验收；它不是 pbr 对任意 DNAT 场景的保证。若任一前提不成立，简单 C 规则不足，但仍先记录证据再决定是否需要 conntrack mark。

## 官方事实

### fw4 redirect、hook 和路由查找

- firewall4 官方示例使用 `config redirect` 将 WAN 端口 DNAT 到 LAN 主机；官方解析器接受 `src_ip`、`src_dip`、`src_dport`、`dest_ip` 和 `dest_port`。在 DNAT 规则中，`src_dip` 是转换前的公网目的地址匹配，`dest_ip/dest_port` 是转换后的内网目标，`src_ip` 可用于 ACK EIP allowlist。[firewall4 默认配置](https://github.com/openwrt/firewall4/blob/master/root/etc/config/firewall)、[fw4 UCI 解析源码](https://github.com/openwrt/firewall4/blob/master/root/usr/share/ucode/fw4.uc)
- fw4 生成 `table inet fw4`，并提供 `mangle_prerouting`、`mangle_forward`、`mangle_output` 等链；`mangle_prerouting` 使用 `hook prerouting priority mangle`，在路由决定前可处理 packet mark。[fw4 ruleset 模板](https://github.com/openwrt/firewall4/blob/master/root/usr/share/firewall4/templates/ruleset.uc)
- `/usr/share/nftables.d/chain-pre/<chain>/` 和 `chain-post/<chain>/` 是 fw4 官方支持的链内插入位置，`/etc/nftables.d/*.nft` 可在 `inet/fw4` 表上下文中自动 include。[fw4 nftables.d README](https://github.com/openwrt/firewall4/blob/master/root/usr/share/nftables.d/README)
- Linux RPDB 按优先级扫描规则，`fwmark[/mask]` 可选择路由表；OpenWrt netifd 的 `option mark` 是同一个字符串（例如 `0x100/0xff`），不是分开的 `option mask`。MVP 不新增 netifd rule，先由 pbr 管理接口表。[OpenWrt IP rules](https://openwrt.org/docs/guide-user/network/routing/ip_rules)、[netifd iprule.c](https://github.com/openwrt/netifd/blob/master/iprule.c)

### NAT、conntrack 与 C 规则的推导边界

- nftables NAT 规则在连接的首包上建立 conntrack NAT 映射，后续包使用该映射；DNAT 通常位于 prerouting，SNAT 位于 postrouting。[nftables NAT](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT))
- nftables 官方给出 `ct mark set meta mark` 保存 packet mark、`meta mark set ct mark` 恢复的语法。[packet/conntrack mark](https://wiki.nftables.org/wiki-nftables/index.php/Setting_packet_metainformation)
- pbr 1.2.2 官方脚本把 `pbr_prerouting`/`pbr_forward`/`pbr_output` 接入 fw4 mangle 链并使用 packet mark；该脚本没有为本场景自动保存/恢复 `ct mark`。[pbr init 源码](https://github.com/stangri/pbr/blob/1.2.2/files/etc/init.d/pbr)

因此 C 的预期包序列是（第二行是标准 NAT 语义上的推导，现场必须验证）：

```text
ACK_EIP -> MOBILE_PUBLIC:443
  fw4 DNAT/prerouting -> HARBOR_LAN:443 -> 路由到 Harbor

HARBOR_LAN -> ACK_EIP:临时端口
  pbr source+destination policy -> Mobile 路由表
  conntrack reverse-SNAT/postrouting -> MOBILE_PUBLIC:443 -> ACK_EIP
```

同一个 Mobile 公网地址同时作为 DNAT 目标和出站 SNAT 源，不会自动使路由器混淆连接；conntrack 用五元组和 NAT 映射区分方向。真正的判别条件是回包在路由决策前仍有稳定的 Harbor 源地址和 ACK EIP 目的地址。若回包先被其他 NAT/代理改写，C 不再可靠。

### pbr、域名集合和严格阻断

- pbr policy 的字段包括 `interface`、`src_addr`、`dest_addr`、`src_port`、`dest_port`、`proto` 和 `chain`；默认链是 `prerouting`，策略在配置中的声明顺序决定优先级。[pbr policy options](https://docs.openwrt.melmac.ca/pbr/#policy-options)
- `resolver_set 'dnsmasq.nftset'` 依赖支持 nftset 的 `dnsmasq-full`；域名策略要求客户端使用路由器 dnsmasq。外部 DNS、DoH/DoT 或 OpenClash Fake-IP/DNS 劫持可能使 set 没有实际连接地址。[pbr dnsmasq nftset](https://docs.openwrt.melmac.ca/pbr/#use-dnsmasq-nft-sets-support)
- `strict_enforcement` 默认启用；目标接口不可用时，匹配策略的转发应被阻止而不是泄漏到默认 WAN。它不改变未匹配流量的主路由；重载/崩溃后的行为仍需现场观察。[pbr strict enforcement](https://docs.openwrt.melmac.ca/pbr/#strict-enforcement)

## MVP 规则草案（全部地址为占位）

### pbr

仅在确认接口名确实为 `mobile`、`unicom` 后，把以下作为最小草案；不添加默认 Mobile policy：

```uci
config pbr 'config'
        option enabled '1'
        option resolver_set 'dnsmasq.nftset'
        option strict_enforcement '1'
        option ipv6_enabled '0'       # IPv6 另行验收

config policy
        option name 'argo-ack-api-mobile'
        option interface 'mobile'
        option src_addr '<ARGO_IP_OR_CIDR>'
        option dest_addr '<ACK_API_FQDN_OR_IP>'
        option dest_port '<KUBECONFIG_SERVER_PORT>'
        option proto 'tcp'
        option chain 'prerouting'

config policy
        option name 'uploader-oss-mobile'
        option interface 'mobile'
        option src_addr '<UPLOADER_IP_OR_CIDR>'
        option dest_addr '<BUCKET_ENDPOINT_OR_CNAME>'
        option dest_port '443'
        option proto 'tcp'
        option chain 'prerouting'

config policy
        option name 'harbor-reply-to-ack-mobile'
        option interface 'mobile'
        option src_addr '<HARBOR_LAN_IP>/32'
        option dest_addr '<ACK_FIXED_EIP>/32'
        option proto 'tcp'
        option chain 'prerouting'
```

说明：

- A 的目的端口必须来自 kubeconfig `server`，不能默认写 443；ACK API 可能使用其他端口。
- B 只覆盖确认过的 OSS data endpoint。若 SDK 先访问 STS、RAM 或自定义 CNAME，先从日志/DNS 记录这些精确域名，再单独登记服务类；不要扩大成阿里云总网段。
- C 不写 `dest_port '443'`：Harbor 回包的目的端口是 ACK 发起连接时的临时端口；可选的 `src_port '443'` 只有在现场确认 Harbor 始终从 443 回包时才添加。
- 同一 uploader 若同时下载，B 会把该 endpoint 的下载也带到 Mobile；要区分上传/下载，必须使用独立源主机/网段，或接受同 endpoint 同出口。MVP 不引入应用级 socket mark。
- 所有未匹配流量依赖主路由表默认联通；用 `ip -4 rule show` 确认 pbr 规则优先、`main` 仍以联通为默认。

### fw4 443 DNAT（不新增 DMZ/自定义 nft）

沿用现有 Mobile WAN zone 和现有 LAN/office zone，只添加一个源 allowlist 的 443 redirect；zone 名称必须按现场 UCI 替换：

```uci
config redirect 'harbor-https-from-ack'
        option name 'Harbor HTTPS from ACK EIP'
        option family 'ipv4'
        option src 'mobile'
        option src_ip '<ACK_FIXED_EIP>/32'
        option src_dip '<MOBILE_PUBLIC_IP>/32'
        option src_dport '443'
        option dest 'lan'
        option dest_ip '<HARBOR_LAN_IP>'
        option dest_port '443'
        option proto 'tcp'
        option reflection '0'
```

这是“只对 ACK EIP 开放 Mobile 公网 443”的草案，不是可直接提交的配置。保持 Mobile zone 其他入站默认拒绝；Harbor 本机防火墙再次限制 ACK EIP，并让证书 SAN 覆盖 ACK 使用的 Harbor FQDN。是否需要 Mobile 出站 masquerade 取决于运营商把 `/27` 作为 routed block 还是 NAT 链路，不能在未知交付模型时盲加 `masq`。

## OpenClash 最小旁路要求

OpenClash 的 TUN/Mix 路径会在 nft mangle 链使用 fwmark 和独立路由表；其官方源码和 README 也要求按安装模式准备 TUN/tproxy/dnsmasq 依赖。[OpenClash README](https://github.com/vernesong/OpenClash/blob/master/README.md)、[OpenClash firewall/init 源码](https://github.com/vernesong/OpenClash/blob/dev/luci-app-openclash/root/etc/init.d/openclash)

MVP 只需要：

1. 将 ACK API FQDN/IP、OSS endpoint/CNAME 和 Harbor FQDN 标成 OpenClash `DIRECT`/绕过，不让它们进入代理/TUN；精确字段名随安装版本变化，不能把未核对的 UCI key 写进基线。
2. 这些域名若依赖 pbr `dnsmasq.nftset`，必须让 uploader/Argo 使用路由器 dnsmasq；否则改用现场确认的 IP 集合。Fake-IP、DoH/DoT、DNS 劫持必须关闭、旁路或单独验证。
3. 选择唯一的 mark/table owner：OpenClash 旁路后由 pbr 选择 Mobile；不要同时让 OpenClash 和 pbr 对同一流决定出口。用 `nft list ruleset` 和 `ip rule` 检查是否出现 `0x162` 等 OpenClash mark 抢占。
4. Harbor 入站 DNAT 不应被代理；只允许 Mobile 443 redirect 和 ACK EIP。若 OpenClash 模式仍捕获 C 的回包，MVP 判定未通过，不先添加自定义 nft。

## 事实保证、推论和必须测试的项目

### 可以直接据官方资料确认的事实

- fw4 有源/目的地址和端口 redirect 字段，pbr 有源/目的地址、端口、协议和接口 policy；默认主路由可保留联通。[fw4 UCI](https://github.com/openwrt/firewall4/blob/master/root/usr/share/ucode/fw4.uc)、[pbr policy options](https://docs.openwrt.melmac.ca/pbr/#policy-options)
- NAT 连接由 conntrack 维护，DNAT/SNAT 具有对应的 prerouting/postrouting 语义；packet mark 与 conntrack mark 是不同对象。[nftables NAT](https://wiki.nftables.org/wiki-nftables/index.php/Performing_Network_Address_Translation_(NAT))、[nftables marks](https://wiki.nftables.org/wiki-nftables/index.php/Setting_packet_metainformation)
- pbr 的 `dnsmasq.nftset` 需要路由器 DNS，`strict_enforcement` 可阻止目标 WAN 故障时的匹配流量泄漏。[pbr dnsmasq nftset](https://docs.openwrt.melmac.ca/pbr/#use-dnsmasq-nft-sets-support)、[pbr strict enforcement](https://docs.openwrt.melmac.ca/pbr/#strict-enforcement)
- Kubernetes 私有 registry 的 `imagePullSecret` 必须与 Pod 同 namespace；镜像 digest 是稳定引用，tag 可以移动。[Kubernetes images](https://kubernetes.io/docs/concepts/containers/images/)、[private registry Secret](https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/)
- Argo CD controller/repo-server 可在本地通过 kubeconfig 指向 ACK API；Git 与 ACK API 是控制面，不应将镜像层规则混成 Alibaba 总网段。[Argo CD architecture](https://argo-cd.readthedocs.io/en/stable/operator-manual/architecture/)

### 本文的工程推论

- A/B 的源+精确目的 pbr policy 不需要额外 conntrack mark，因为连接由本地源主机发起，Mobile 出口 NAT/conntrack 会把响应带回同一路径。
- C 的 Harbor 源+ACK EIP 目的 policy 可在标准 DNAT/reverse-SNAT 顺序下为回包选 Mobile；同一 Mobile 公网地址可同时作为 DNAT 目标和 reverse-SNAT 源。
- 这些推论依赖固定 EIP、未被其他 NAT/代理改写的 tuple 和单一 mark owner，不是“任意双 WAN DNAT 都对称”的保证。

### 必须现场验证，不能假定

- 移动 `/27` 是 routed 还是 NAT、网关/下一跳、ARP/anti-spoof、MTU、入站端口限制，以及是否确有可用的单一 Mobile 公网地址。
- ACK EIP 是否始终是节点对外 SNAT 地址；节点池、故障切换或 ACK 组件是否会使用其他 EIP。
- kubeconfig `server` 的实际 FQDN/IP/端口是否可从 Mobile 到达；API 响应是否确实从 Mobile 返回。
- Harbor reply 在 `mangle_prerouting` 中是否仍是 `src=HARBOR_LAN_IP,dst=ACK_EIP`，以及 C 规则是否在路由 lookup 前命中。
- Harbor 回包经过 reverse-SNAT 后是否从 Mobile 公网地址发出；任何一包从联通返回都表示 C 失败。
- OSS endpoint/CNAME 的 A/AAAA、TTL、STS/RAM/认证辅助域名；官方 OSS 资料提供 region endpoint 和 `DescribeRegions`，没有适合硬编码公网出口的统一 CIDR 清单。[OSS Regions/endpoints](https://www.alibabacloud.com/help/en/oss/user-guide/regions-and-endpoints)、[DescribeRegions](https://www.alibabacloud.com/help/en/oss/developer-reference/describeregions)
- OpenClash 当前 TUN/Mix、Fake-IP、DoH/DoT、fwmark/table 以及 pbr 生成链的实际顺序。
- IPv6 是否存在；`ipv6_enabled=0` 只表示 MVP 暂不把 IPv6 宣称为 Mobile，不能阻止应用自行走 AAAA，必须另行禁用或建立已验收的 v6 策略。

## 只读/隔离验证步骤

1. **保存基线**：脱敏导出 `network`、`firewall`、`pbr`、OpenClash 配置，以及 `ip -4 rule show`、`ip -4 route show table all`、`nft list ruleset`；确认主表默认路由为联通、Mobile pbr 表存在。
2. **验证 DNS 集合**：确认 `dnsmasq-full` 支持 nftset；从 Argo/uploader 查询实际 endpoint，查看 pbr/dnsmasq 生成的集合元素和 TTL。若 OpenClash 接管 DNS，先做 DIRECT/旁路矩阵。
3. **验证 A**：在维护窗口用已授权的只读 ACK API 请求，抓 `<mobile>`/`<unicom>`、`ip rule` 计数和 kube API 日志；确认请求与响应均使用 Mobile，Mobile 故障时不泄漏到联通。
4. **验证 B**：用最小权限 OSS 凭据上传一个非敏感小对象，记录实际 data endpoint 及认证辅助域名；确认仅 uploader 到该 endpoint 命中 Mobile，未匹配普通下载仍走联通。
5. **验证 C 入站**：从 ACK 固定 EIP 发起 Harbor `/v2/` 和一个小 digest pull；从非 allowlist 地址只应被拒绝。路由器上同时观察 `tcpdump -ni <mobile>`、`tcpdump -ni <unicom>`、`conntrack -L`、`nft -a list chain inet fw4 mangle_prerouting`；确认 Harbor 回包在 reverse-SNAT 后全部离开 Mobile。
6. **验证 C 规则 tuple**：在 Harbor 回包进入路由器时确认 `src=<HARBOR_LAN_IP>`、`dst=<ACK_FIXED_EIP>`，且没有目的端口 443 限制；若源/目的已被改写或规则未命中，记录为“简单 C 不成立”，不要未经证据添加 custom nft。
7. **验证 OpenClash**：停止、redir-host、TUN/Mix 仅在隔离测试源上各测一次；检查三类流是否唯一由 pbr/Mobile owner 处理、未被代理 mark/TUN 表改道。
8. **验证 IPv6/恢复**：对实际 endpoint 做 `dig A/AAAA`、`curl -4/-6`；测试 pbr/OpenClash 重载和 Mobile 断链后的旧 conntrack，不执行公网扫描或压力测试。

## 未解决问题

- 移动 `/27` 的 routed/NAT 交付、Mobile 公网地址和下一跳是什么？是否允许入站 443、是否有 anti-spoof/端口 ACL？
- ACK 固定 EIP 是否是所有节点、所有拉取和故障切换期间的唯一外部源？
- Argo kubeconfig `server` 精确 endpoint/端口是什么，且 Mobile 是否是组织要求的优先路径？
- Harbor 内网地址、实际监听端口、默认网关和本机 ACK EIP allowlist 是否确认？
- OSS bucket region、实际 endpoint/CNAME、STS/RAM 辅助域名和 IPv6 行为是什么？
- uploader 是否专用主机/网段；同一源是否还必须把 OSS 下载留在联通？
- OpenClash 是否启用 TUN/Mix、Fake-IP、DoH/DoT，当前 mark/table owner 是谁？
- IPv6 是否必须支持这三类流；若必须，何时单独设计 Mobile/Unicom v6 policy？

## 来源索引

本文仅引用 OpenWrt firewall4/netifd、pbr、nftables、Alibaba Cloud OSS、Argo CD、Kubernetes、Harbor 和 OpenClash 的官方文档或上游源码。所有地址、接口、EIP、DNS、端口、mark/table 和证书均为占位；事实、工程推论和待测条件已分开。本文不执行任何路由器/云端变更，不引入 ACR、mwan3、隧道、DMZ 或预先自定义 nft。
