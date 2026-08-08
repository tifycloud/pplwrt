# CompanyWrt（小米 AX9000 企业边界候选固件）

CompanyWrt 是基于官方 OpenWrt **25.12.5**、`qualcommax/ipq807x`、标准
`xiaomi_ax9000` profile 的可审计 ImageBuilder 工程。当前版本是
**25.12.5-company.2-rc1**：它是 release candidate，**不是生产稳定版**。
在真实 AX9000 完成刷写/救援/断电/双 WAN/无线/安全门禁前只能用于实验室。

> 固件文件名相似不等于设备兼容。错误变体、secure boot 状态、分区或启动槽
> 可能导致变砖。当前从 kwrt 迁移的设备必须先按 [刷机与救援](docs/flash.md)
> 收集 board、MTD、boot slot 和恢复证据，不能直接运行 sysupgrade。

## 构建与信任链

发布构建固定官方 ImageBuilder URL/SHA，使用仓库外的 `usign` 私钥签署严格
`RELEASE-MANIFEST`；固件内只嵌入 [公开验证密钥](keys/companywrt-release.pub)。
私钥不得进入 git、overlay、日志或 artifact。

```sh
export USIGN_SECRET_KEY_FILE=/secure/outside/repository/companywrt-usign.key
./scripts/build-in-container.sh --profile xiaomi_ax9000 --channel rc
cd artifacts/rc/25.12.5-company.2-rc1
sha256sum -c SHA256SUMS
```

输出按 `artifacts/<channel>/<VERSION>/` 版本化，包含固件、严格 manifest、
`RELEASE-MANIFEST.sig`、包清单、增强 CycloneDX SBOM、NOTICE、MIT LICENSE、
内容核查报告和 SHA256SUMS。CI 的只读 build job、attestation job 与 contents-write 发布 job
分离；RC tag 自动发布 prerelease。正式 stable 没有真机证据文件就会失败。

## 默认边界

- 网络脚本只有 **plan** 模式，不会 `uci import`、commit、reload 或 live apply。
  角色固定为 `unicom`（1G、office 默认）和 `mobile`（100M、稳定上传）。
- LuCI dashboard 只显示 UCI/构建配置快照；“已启用”不等于运行健康或真机验收。
- 首启启用 HTTP→HTTPS redirect，不设置默认密码、不猜 DSA/WAN、不放宽 WAN 入站。
  首次登录只允许隔离有线 LAN，并运行 `enrollment-preflight`。
- WireGuard、logd 远程日志能力和轻量 collectd 监控基础预装；密钥、collector、
  VLAN 和租户配置不入镜像。SQM 不预装，移动链路有审阅模板，联通默认禁用。
- OpenClash 本体、mihomo 核心、订阅与规则不打包，只预装官方 feed 可解析依赖。
- 自定义 LuCI/脚本当前以 ImageBuilder `FILES` overlay 安装，明确命名为
  `*-overlay`；仓库中的 Makefile 不是已构建 APK 的声明。
- 官方 LuCI 主题始终保留为救援入口；Wi-Fi 配置值为 HE80，HE160 只做专项实测。

从 [文档导航](docs/README.md) 开始，刷写前必读 [安全基线](docs/security.md)、
[OTA](docs/ota.md) 和 [生产测试矩阵](docs/test-matrix.md)。
