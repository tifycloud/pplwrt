# CompanyWrt（小米 AX9000 企业边界候选固件）

CompanyWrt 是基于官方 OpenWrt **25.12.5**、`qualcommax/ipq807x` 的可审计企业固件。
本仓库当前唯一可构建目标是为用户实机验证的暗云 Boot 单 UBI 大分区新建的
`xiaomi_ax9000_darkyun` profile；它不是官方标准 `xiaomi_ax9000` 镜像。当前版本是
**25.12.5-company.2-rc3**：它是 release candidate，**不是生产稳定版**。
在真实 AX9000 完成刷写/救援/断电/双 WAN/无线/安全门禁前只能用于实验室。

> 官方标准 AX9000 镜像和历史 `company.1/company.2-rc1` 都与本机单 UBI 布局不兼容，
> **禁止刷入**。第一次迁移必须先运行只读 `ax9000-darkyun-preflight`，并完成签名、DTB、
> 救援和人工刷机门禁；仓库绝不自动执行 sysupgrade。

## 构建与信任链

发布构建固定官方 OpenWrt tag/commit 与已锁定 feed commit，应用一份可审计设备补丁，
通过完整 Buildroot 编译内核、DTB 和 sysupgrade，再使用仓库外的 `usign` 私钥签署严格
`RELEASE-MANIFEST`；固件内只嵌入 [当前公开验证密钥](keys/companywrt-release.pub)。
私钥不得进入 git、overlay、日志或 artifact。

RC2 已完成显式 usign 轮换过渡；RC3 使用固件内当前 key 对 manifest 主签，不再读取或
使用旧 RC1 私钥。当前私钥只存在受审批和冷却保护的 `firmware-signing` environment
secret；详见 [密钥说明](keys/README.md)。

```sh
./scripts/build-in-container.sh --profile xiaomi_ax9000_darkyun --channel rc --compile-only
export USIGN_SECRET_KEY_FILE=/secure/outside/repository/companywrt-usign-current.key
./scripts/sign-release-bundle.sh \
  --input artifacts/preflight/25.12.5-company.2-rc3 --channel rc
cd artifacts/rc/25.12.5-company.2-rc3
sha256sum -c SHA256SUMS
```

输出按 `artifacts/<channel>/<VERSION>/` 版本化，包含固件、严格 manifest、
`RELEASE-MANIFEST.sig`、包清单、增强 CycloneDX SBOM、NOTICE、MIT LICENSE、
内容核查报告和 SHA256SUMS。CI 先证明 annotated tag 的 peeled commit 与受保护
`origin/main` HEAD 精确相等；完整 Buildroot 在无 secret job 中完成并封存 checksum，
`firmware-signing` job 只验包和签名、不运行编译器或网络下载。attestation 与唯一
contents-write publish job 继续分离。RC tag 自动发布 immutable prerelease。正式 stable 没有
精确真机 evidence 文件就会失败，RC3 没有真机证据，不能当 stable。

## 默认边界

- 网络脚本只有 **plan** 模式，不会 `uci import`、commit、reload 或 live apply。
  角色固定为 `unicom`（1G、office 默认）和 `mobile`（100M、稳定上传）。
- LuCI dashboard 只显示 UCI/构建配置快照；“已启用”不等于运行健康或真机验收。
- 首启启用 HTTP→HTTPS redirect，不设置默认密码、不猜 DSA/WAN、不放宽 WAN 入站。
  首次登录只允许隔离有线 LAN，并运行 `enrollment-preflight`。
- WireGuard、logd 远程日志能力和轻量 collectd 监控基础预装；密钥、collector、
  VLAN 和租户配置不入镜像。SQM 不预装，移动链路有审阅模板，联通默认禁用。
- OpenClash 本体、mihomo 核心、订阅与规则不打包，只预装官方 feed 可解析依赖。
- 自定义 LuCI/脚本当前以 Buildroot `files/` overlay 安装，明确命名为
  `*-overlay`；仓库中的 Makefile 不是已构建 APK 的声明。
- 官方 LuCI 主题始终保留为救援入口；Wi-Fi 配置值为 HE80，HE160 只做专项实测。

从 [文档导航](docs/README.md) 开始。准备迁移这台已采证的暗云 Boot AX9000 时，按
[全新安装教程](docs/fresh-install.md)执行；刷写前同时必读 [安全基线](docs/security.md)、
[OTA](docs/ota.md) 和 [生产测试矩阵](docs/test-matrix.md)。
