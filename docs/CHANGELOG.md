# Changelog

## 25.12.5-company.2-rc2 — 2026-08-08

**Release candidate / NOT PRODUCTION.** 仍无 AX9000 真机 production-gate 证据；本轮只加固
静态、构建、签名与发布门禁，不创建 stable tag。RC2 尚未发布，随后根据实机证据把
构建目标改为暗云 Boot 单 UBI 专属变体。

- 真机只读确认 MIBIB 为 `rootfs=0x01180000+0x0e800000`，两个 APPSBL 指纹一致，运行时
  为单 UBI `kernel/rootfs/rootfs_data`；历史标准布局 RC 明确禁止刷入。
- 从官方 ImageBuilder 切换为固定 OpenWrt 25.12.5/feeds commit 的完整 Buildroot；新增
  `xiaomi_ax9000_darkyun` DTS/profile/board/upgrade patch，不生成 factory 镜像。
- 新增 MIBIB/APPSBL/MTD/UBI 只读迁移 preflight；release manifest、OTA、production gate
  绑定专属 board、partition variant 和 bootloader 指纹。
- inspector 从 sysupgrade FIT 提取 DTB，拒绝 `ubi_kernel`，要求 232 MiB rootfs、cfg_bak、
  `/dev/ubiblock0_1` 与专属 compatible 全部吻合。

- 发布必须使用 annotated `v$VERSION` tag，且 peeled commit 与实时拉取的受保护
  `origin/main` HEAD 精确相等；签名 job 绑定 `firmware-signing` environment（审批、冷却、
  仅 `main` branch/`v*` tag policy）。active tag ruleset 禁止 `v*` 删除/非 fast-forward，
  仍允许合法新 RC tag。
- 开启 GitHub 原生 immutable releases；先上传完整 draft 再发布，发布后逐资产比对 digest，
  并验证 GitHub release attestation 和每个本地资产。
- 完成 RC1→RC2 显式 usign 轮换：旧 key 主签保证 RC1 可升级，新 key 共签并嵌入 RC2；
  新私钥只存 environment secret，RC2 核验后删除旧 repository secret。
- 固件 inspector 实际读取解包 rootfs `/etc/shadow`；只接受 root 密码字段 EMPTY 或 LOCKED，
  拒绝任意预置 hash，报告具体状态且不输出 hash。
- RC 证据状态固定为 `NOT_PERFORMED_RC_ONLY`。stable 构建必须读取且验证精确 gate 文件，
  把 `VERIFIED`、gate SHA、opaque hardware/serial evidence IDs 和被测固件 SHA 写入
  BUILD-METADATA、内容报告与严格 v2 release manifest，并要求构建 SHA 精确相等。
- CycloneDX 以构建出的 251 个唯一 PACKAGE-MANIFEST 包为基准建立一一上游组件映射；
  补齐 `libnghttp2-14` 缺项。无法从上游 SBOM 证明的许可证写 `NOASSERTION`，不宣称
  完整许可证结论。
- network plan 对 domain 大小写、IPv4 `/32`、CIDR host bits、单端口范围做规范化，拒绝
  mobile/unicom 间相同或重叠 destination/port policy。
- 设备端 `ota-apply` 的生产 trust anchor 固定为 `/etc/companywrt/keys/release.pub`；
  `--public-key` 只在显式、双重环境保护的临时 test mode 可用。standalone `ota-check`
  仍允许离线 CI 指定公钥。
- ShellCheck 扩展到 `tests/**/*.sh` 并清零告警；新增 shadow inspector、SBOM 一一覆盖、
  v2 hardware manifest、OTA key override 和网络规范化冲突测试。

## 25.12.5-company.2-rc1 — 2026-08-08

**Release candidate / NOT PRODUCTION.** 无 AX9000 真机 production-gate 证据；只能实验室验证。

- 网络改为严格 plan-only incremental UCI；移除 `uci import`、live apply/伪回滚；加入
  unicom/mobile 明确角色、server/employee/域名/IP/CIDR/端口 policy 与注入/重复校验。
- OTA 加入严格 15 字段 schema、HTTPS-only、usign 信任锚/签名、实际 SIZE/SHA 下载校验；
  apply 二次绑定 board/profile/release/version/channel、`sysupgrade -T` 和版本+SHA 双确认。
- 首启启用 HTTPS redirect、不嵌密码/不改 WAN firewall；加入只读 enrollment preflight。
- dashboard 改为动态 UCI/构建快照，移除静态健康/ready/pass 声明，保留响应式和官方主题。
- 构建输出按 channel/version 分目录，补 WireGuard/logd/collectd，SQM mobile 可选模板；
  custom overlay 进入 manifest、增强 CycloneDX SBOM、NOTICE 和固件解包内容报告。
- CI 拆分只读 build、attestation 与 contents-write publish；checkout 不留 credentials，
  tag/VERSION、RC prerelease、stable 真机证据门禁和 usign secret fail-closed。
- 增补中国/国际变体与 secure boot 不确定性、kwrt 迁移采集、生产门禁/救援文档。

## 25.12.5-company.1 — 2026-08-08

- 初始 ImageBuilder/profile、LuCI/PBR/双 WAN/OTA 工程骨架。
- 该版本 release 已标记 prerelease / NOT PRODUCTION，不应刷写生产设备。
