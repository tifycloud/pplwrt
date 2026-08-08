# 文档导航

| 主题 | 文档 |
| --- | --- |
| 设计边界、组件和数据流 | [architecture.md](architecture.md) |
| 版本与长期维护 | [roadmap.md](roadmap.md) |
| 可复现构建、校验和容器 | [build.md](build.md) |
| AX9000 刷机与救援 | [flash.md](flash.md) |
| 第一次启动 | [first-config.md](first-config.md) |
| 双 WAN、PBR 和 fwmark | [dual-wan-pbr.md](dual-wan-pbr.md) |
| VLAN/WireGuard | [vlan-wireguard.md](vlan-wireguard.md) |
| 安全基线与机密 | [security.md](security.md) |
| OpenClash 依赖和冲突 | [openclash.md](openclash.md) |
| 官方/USTC/TUNA 源 | [feeds.md](feeds.md) |
| CompanyWrt UI | [ui.md](ui.md) |
| OTA、人工确认和发布 | [ota.md](ota.md) |
| RC/生产真机门禁 | [test-matrix.md](test-matrix.md) |
| 贡献流程 | [contributing.md](contributing.md) |
| 变更记录 | [CHANGELOG.md](CHANGELOG.md) |
| 官方一手来源与校验证据 | [sources.md](sources.md) |

当前版本是 RC/NOT PRODUCTION。任何会改变设备状态的命令都标明 `管理员确认`；接口名、
VLAN ID、地址、密钥和订阅都是示例，不能直接复制到生产网络。当前从 kwrt 迁移的设备
应先读 flash.md 并采集 board/MTD/boot slot/secure boot/救援证据。
