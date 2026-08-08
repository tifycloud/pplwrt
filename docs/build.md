# 构建、签名与内容证据

官方 target 目录：<https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/>。
固定 ImageBuilder 与 SHA256 记录在 `devices/ax9000/profile.json`；脚本还会检查 URL、
profile 和官方 archive SHA。host helper 仅支持 Linux x86_64。

## Linux/amd64 或容器构建

完整构建必须提供与 `keys/companywrt-release.pub` 匹配、且位于仓库外的私钥：

```sh
USIGN_SECRET_KEY_FILE=/secure/companywrt-usign.key \
  ./scripts/build-in-container.sh --profile xiaomi_ax9000 --channel rc
```

原生 Linux x86_64 可直接运行 `build-imagebuilder.sh`。Apple Silicon 使用容器脚本；
容器固定 `ubuntu:24.04` 和 `linux/amd64`，安装 squashfs 内容核查工具。默认目录为：

```text
artifacts/rc/25.12.5-company.2-rc1/
artifacts/beta/25.12.5-company.2-beta1/  # 仅 -betaN VERSION 的显式 beta 构建
```

现有输出目录不会被静默覆盖。`--print-output` 可只检查目录/版本/channel 解析。
完整构建还要求 git worktree 干净、source commit 等于 HEAD；固件输入目录若含被 git
忽略的 secret-like 文件也会失败，避免本地未跟踪配置被悄悄嵌入却仍声称来自某 commit。

## 产物与检查

构建完成前必须全部成功：

1. official ImageBuilder archive SHA 与 profile metadata；
2. 包解析（包括 usign、WireGuard、logd、collectd；不含 mwan3/SQM）；
3. sysupgrade tar 布局和 squashfs 解包；
4. VERSION/build.conf/公钥/OTA/网络/preflight/LuCI/首启 HTTPS 文件存在；
5. 官方 loopback/DSA/WAN6 生成逻辑、WAN/WAN6 REJECT zone 和默认 firewall rules 保留；
   首启 overlay 不含默认密码或 WAN ACCEPT；
6. custom overlay 进入 CUSTOM-COMPONENTS、NOTICE、MIT LICENSE 和 CycloneDX SBOM；
7. 私钥与公钥指纹一致后签署 RELEASE-MANIFEST，并用公钥回验；
8. 所有 release 文件生成 SHA256SUMS 并立即回验。

`packages/luci-*-company/Makefile` 是未来官方 SDK 打包入口。本项目当前没有把它们
编译成 APK；ImageBuilder 直接复制 `root/` 树，因此 SBOM 名称为
`luci-*-company-overlay`。切换为 SDK APK 前须新增独立、固定 SDK 构建链和 APK
签名/安装测试，不能把 overlay 冒充包，也不为此切换完整 Buildroot。

## CI 权限与发布

- `CompanyWrt CI / checks`：`contents: read`，checkout 不持久化 credentials。
- release build：`contents: read`，secret 缺失即失败；上传 workflow artifact。
- attestation：只增加 `id-token: write`、`attestations: write`，生成 Sigstore provenance。
- publish：只下载已构建 artifact，唯一具有 `contents: write` 的 job。
- tag 必须精确等于 `v$(cat VERSION)`；RC/beta 自动 prerelease。
- stable 必须存在 `production-gates/<VERSION>.env` 且全部真机项 PASS；模板不能通过。
- stable 构建出的 sysupgrade SHA 必须与证据文件 `FIRMWARE_SHA256` 完全一致；包仓库或
  任意源码漂移都会令发布失败并要求重做真机验收。

为使“先构建并真机测试、再提交证据文件、最后从同一源码发布”可验证，设备内
`build.conf` 只含 profile/release/channel。精确 source commit 仍写入签名
`RELEASE-MANIFEST`、BUILD-METADATA 和 GitHub attestation；若把 commit 写进 rootfs，
提交包含固件 hash 的证据文件会改变 commit 和固件本身，形成无法闭合的自引用。

验证 GitHub provenance：

```sh
gh attestation verify path/to/sysupgrade.bin -R tifycloud/pplwrt
```
