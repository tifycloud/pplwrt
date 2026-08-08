# 构建、签名与内容证据

官方 OpenWrt `v25.12.5` 固定到 commit
`f0a60eee2fe051741c643ea6118718aae1ef17fb`，feeds 继续使用该 tag 自带的 commit 锁。
`devices/ax9000/patches/` 只增加 `xiaomi_ax9000_darkyun` 设备树、profile、板级映射和
单 UBI 升级分支。构建脚本核对 tag peeled commit、patch SHA、profile 与
`supported_devices=["xiaomi,ax9000-darkyun"]`，只支持 Linux x86_64。

## Linux/amd64 或容器构建

完整 Buildroot 编译必须在**没有私钥**的环境先完成。RC2 是一次性 transition release：
隔离签名步骤需要旧 key 主签和当前 key 共签，两个路径都必须在仓库外；正式 RC2 由
`firmware-signing` environment 提供，不从开发机复制长期 secret。

```sh
USIGN_SECRET_KEY_FILE=/secure/companywrt-usign-previous.key \
USIGN_CURRENT_SECRET_KEY_FILE=/secure/companywrt-usign-current.key \
  ./scripts/sign-release-bundle.sh \
    --input artifacts/preflight/25.12.5-company.2-rc2 --channel rc
```

原生 Linux x86_64 可直接运行 `build-buildroot.sh`。Apple Silicon 使用容器脚本；
容器固定 `ubuntu:24.04` 和 `linux/amd64`，使用 Docker named volume 提供大小写敏感的
源码/编译缓存。先在干净 commit 上运行唯一允许的编译阶段：

```sh
./scripts/build-in-container.sh --profile xiaomi_ax9000_darkyun --channel rc --compile-only
```

该目录含 `COMPILE-ONLY-NOT-A-RELEASE.txt`，绝不能刷机或发布。正式默认目录为：

```text
artifacts/rc/25.12.5-company.2-rc2/
artifacts/beta/25.12.5-company.2-beta1/  # 仅 -betaN VERSION 的显式 beta 构建
```

现有输出目录不会被静默覆盖。`--print-output` 可只检查目录/版本/channel 解析。
完整构建还要求 git worktree 干净、source commit 等于 HEAD；固件输入目录若含被 git
忽略的 secret-like 文件也会失败，避免本地未跟踪配置被悄悄嵌入却仍声称来自某 commit。

## 产物与检查

构建完成前必须全部成功：

1. official OpenWrt tag/commit、五个 feed commit、设备 patch SHA 与 profile metadata；
2. 包解析（包括 usign、WireGuard、logd、collectd；不含 mwan3/SQM）；
3. sysupgrade tar 布局、FIT 内 DTB 和 squashfs 解包；DTB 必须是单一
   `rootfs=0x01180000+0x0e800000`、`cfg_bak=0x0f980000+0x00080000`，不得含 `ubi_kernel`；
4. VERSION/build.conf/设备规格/公钥/OTA/迁移 preflight/LuCI/首启 HTTPS 文件存在；
5. 官方 loopback/DSA/WAN6 生成逻辑、WAN/WAN6 REJECT zone 和默认 firewall rules 保留；
   首启 overlay 不含默认密码或 WAN ACCEPT；
6. 暗云大分区目标固定的 252 个唯一 PACKAGE-MANIFEST 包与 CycloneDX 上游组件一一映射；其中包含由
   `CONFIG_LUCI_LANG_zh_Hans` 生成的 Base、PBR、防火墙和软件包管理器中文包；缺失组件补成
   `NOASSERTION`，custom overlay 进入 CUSTOM-COMPONENTS、NOTICE 和 MIT LICENSE；
7. 无密钥编译目录先以 SHA256SUMS 封存；隔离签名 job 重新绑定 commit/内容报告/真机
   evidence，只运行固定 host usign，不运行 make、编译器或网络下载；
8. 私钥与公钥指纹一致后签署 RELEASE-MANIFEST，并用公钥回验；
9. 所有 release 文件生成 SHA256SUMS 并立即回验。

`packages/luci-*-company/Makefile` 是未来官方 SDK 打包入口。本项目当前没有把它们
编译成 APK；Buildroot `files/` 直接复制 `root/` 树，因此 SBOM 名称为
`luci-*-company-overlay`。切换为 SDK APK 前须新增独立、固定 SDK 构建链和 APK
签名/安装测试，不能把 overlay 冒充包。

## CI 权限与发布

- `CompanyWrt CI / checks`：`contents: read`，checkout 不持久化 credentials。
- 无 secret 的 authorize job 先重新 fetch `origin/main`，要求 annotated tag peeled commit、
  checkout commit 和受保护 main HEAD 三者精确相等；旧提交上的任意 `v*` 不能读签名 key。
- release build：`contents: read` 且无 environment/secret，完整 Buildroot、DTB/rootfs inspector
  和 unsigned bundle checksum 都在这里完成。
- release sign：绑定 `firmware-signing` environment；审批、1 分钟 wait timer 和仅
  `main` branch/`v*` tag 的 deployment policy 通过后才可读取 secret。该 job 重新核验
  protected main 和 unsigned SHA，只做 manifest 签名，禁止运行 Buildroot/编译器/下载。
- attestation：只增加 `id-token: write`、`attestations: write`，生成 Sigstore provenance。
- publish：只下载已构建 artifact，唯一具有 `contents: write` 的 job。
- tag 必须是 annotated object 且精确等于 `v$(cat VERSION)`；active `v*` ruleset 禁止删除和
  non-fast-forward，但不阻止新 RC tag；RC/beta 自动 prerelease。
- stable 必须存在 `production-gates/<VERSION>.env` 且全部真机项 PASS；模板不能通过。
- stable 构建出的 sysupgrade SHA 必须与证据文件 `FIRMWARE_SHA256` 完全一致；gate 文件
  SHA、opaque `HARDWARE_EVIDENCE_ID`/`SERIAL_EVIDENCE_ID` 和被测 SHA 同时写入
  BUILD-METADATA、内容报告与签名 v2 manifest。RC/beta 只能写
  `hardware_validation=NOT_PERFORMED_RC_ONLY`。
- release 先建立完整 draft、上传全部资产再发布。仓库开启 GitHub native release
  immutability；publish job 必须回读 `immutable=true`，逐资产比对 API digest，并执行
  `gh release verify` / `verify-asset`。RC1 创建在开关启用前，仍以 tag ruleset、现有 digest
  和历史 attestation 审计；不要把它误称为原生 immutable。

原生 immutable 仍信任 GitHub 身份、仓库设置和 attestation control plane；draft 在发布前
可修改，且该开关不追溯 RC1。因此 workflow 只在完整资产进入 draft 后一次发布，并保留
独立 usign、SHA256SUMS、workflow artifact attestation 和发布后 API digest 多重证据。

为使“先构建并真机测试、再提交证据文件、最后从同一源码发布”可验证，设备内
`build.conf` 只含 profile/board/partition variant/release/channel。精确 source commit 仍写入签名
`RELEASE-MANIFEST`、BUILD-METADATA 和 GitHub attestation；若把 commit 写进 rootfs，
提交包含固件 hash 的证据文件会改变 commit 和固件本身，形成无法闭合的自引用。

验证 GitHub provenance：

```sh
gh attestation verify path/to/sysupgrade.bin -R tifycloud/pplwrt
```
