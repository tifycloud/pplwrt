# 安全首启与运行基线

## 第一次登录

- 只连接隔离的有线 LAN；断开 WAN 与 Wi-Fi 客户端，准备厂商恢复/串口和稳定电源。
- 镜像不嵌入默认密码。首次登录立即设置密码管理器生成的唯一 root 密码。
- release inspector 会实际读取解包 rootfs 的 `/etc/shadow` root 字段；只允许明确的
  `EMPTY` 或 `LOCKED` 初始状态，任意预置 hash 都令构建失败，报告只写状态不写 hash。
- 首启只设置 hostname/中文/CompanyWrt 默认主题和 HTTP→HTTPS redirect；首次向导在有线
  管理员明确输入后才配置主 WAN、Wi-Fi 与密码。OpenWrt2020 仍是救援主题。
- 运行 `/usr/share/company/enrollment-preflight --expected-version ...`。board、target、
  profile/version/channel、root 密码状态、HTTPS、WAN REJECT/DROP、时钟或空间任一失败
  都不能入网。脚本只读且绝不打印密码 hash。
- 自签 HTTPS 首次仍需管理员核对证书指纹；redirect 不等于公开 CA 信任。

## 管理面与 WAN

LuCI/SSH 只允许 LAN/管理 VLAN，WAN zone 和 CompanyWrt uplink zones 必须 REJECT/DROP
入站。每次变更后核对 UCI 以及实际 `nft list ruleset`；dashboard 只显示配置快照，
不作“健康/通过”声明。保留官方 LuCI 主题，避免自定义页面损坏后失去管理入口。

SSH 应使用受管公钥并限制管理网段；密码登录策略、host key 指纹和管理员变更单保存在
加密系统。root 密码、API token、WireGuard/OpenClash 私钥、订阅、完整日志和配置备份
不得进入 git、CI artifact、issue 或公开 release。

## 日志、监控、VPN 与 SQM

- `logd` 可远程 syslog，但明文 syslog 只允许隔离管理 VLAN/WireGuard；模板默认不启用。
- collectd 不进入基础镜像；内置 LuCI/ubus 与只读 `memory-report` 负责首线诊断。需要历史
  指标时再安装经过审阅的 collector/plugin，并经管理 VLAN/WireGuard 传输。
- WireGuard tools/LuCI protocol 预装，peer/AllowedIPs/私钥必须设备本地创建并与 PBR 联审。
- SQM 因 25.12.5 依赖会增加 iptables compatibility，不进基础镜像。只在 mobile 实测后
  按模板安装；unicom 默认禁用，除非独立 CPU/1G throughput 证据通过。

## 固件供应链

OTA 要求 HTTPS、严格 schema、usign、实际 SIZE/SHA、board/profile/channel/version、
`sysupgrade -T` 和双确认。设备端 `ota-apply` 的生产公钥固定为
`/etc/companywrt/keys/release.pub`，禁止操作员用 `--public-key` 改写信任锚；test override
受显式 CLI、环境开关和临时 device root 三重约束。GitHub provenance 是加法防线。
完整 Buildroot job 没有任何发布私钥；其 unsigned bundle 先以 SHA256SUMS 封存。签名 job
只在 annotated tag 精确等于 protected main 且 `firmware-signing` 审批/冷却通过后取 key，
重新验包后只生成 manifest/签名，不运行编译器或网络下载；release 必须由 GitHub 报告
immutable 并通过发布后 digest/attestation 回验。
第三方 APK、OpenClash core、
订阅和规则必须独立核对来源、ABI、签名、许可证和回滚；不得关闭 APK 签名检查。
