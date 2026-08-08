# VLAN、WireGuard 与现场变量

镜像预装 `kmod-wireguard`、`wireguard-tools` 和 `luci-proto-wireguard`，但不写入任何
interface、peer、AllowedIPs 或密钥。VLAN/DSA 拓扑也不预配置，因为端口、租户和地址
属于现场变量。

实施单必须记录 VLAN ID/name/tagged/untagged 端口、IPv4/IPv6、DHCP/DNS、PBR 表、
WireGuard peer 公钥、AllowedIPs、Keepalive、MTU、密钥保管和回滚。先从隔离有线管理
LAN 创建单个 VLAN，验证仍可管理后逐项扩展。

WireGuard 私钥只在设备/受控 secret manager 生成，绝不进入示例、日志、CI 或 issue。
AllowedIPs 会改变路由，应与 unicom/mobile PBR、OpenClash mark/table、IPv6 和 MTU 联合
评审。日志/collectd collector 可经管理 VLAN/WireGuard，到 WAN 的新监听一律禁止。
