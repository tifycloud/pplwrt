# VLAN 与 WireGuard

VLAN 与 WireGuard 不写入稳定镜像或 git，因为端口拓扑、密钥、租户和 MTU 属于现场变量。使用加密的管理员配置库，并把下列信息纳入变更单：VLAN ID/名称/untagged 端口、IPv4/IPv6 前缀、DHCP/DNS、PBR 表、WireGuard peer 公钥、AllowedIPs、Keepalive、MTU 和回滚命令。

实施前确认交换机 trunk 与 AX9000 DSA 设备名；先创建隔离 VLAN，再从有线管理网测试。WireGuard 的 AllowedIPs 可能改变路由选择，必须和 PBR/OpenClash mark 计划联合评审。私钥只在设备密钥库或受控 secret manager，绝不写进示例、日志、CI artifact 或 GitHub issue。
