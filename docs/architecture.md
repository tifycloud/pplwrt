# 架构与可信边界

1. **硬件适配层**：官方 OpenWrt 25.12.5/固定 feeds 为基线；一份审计 patch 新增
   `xiaomi_ax9000_darkyun`、单一 232 MiB rootfs UBI 和同 UBI `nand_do_upgrade`。标准
   `xiaomi_ax9000` 只作上游证据，不是可刷目标。
2. **策略计划层**：命名 `unicom`/`mobile` interface、独立 REJECT uplink zones 和 pbr
   policies；生成器只输出 incremental staging plan，绝不整包 import/live apply。
3. **企业基础能力**：WireGuard、logd、轻量 collectd 预装但无机密/collector；SQM mobile
   可选；OpenClash 仅依赖。PBR/OpenClash/手工 nft 必须单一 mark/table/chain owner。
4. **overlay 管理层**：CompanyWrt LuCI、脚本、模板、首启 redirect。当前通过 FILES
   overlay 安装并在 manifest/SBOM/NOTICE 标为 `overlay-not-apk`；Makefile 不等于 APK。
5. **发布信任层**：固定 Buildroot commit/feed/patch、FIT DTB 与 squashfs 内容检查、
   严格 usign manifest、SIZE/SHA、
   annotated tag=protected main、无密钥 Buildroot job、只验包/签名的 `firmware-signing`
   environment、tag ruleset、GitHub
   immutable release/attestation、最小权限 job、RC prerelease 与 stable 真机证据门禁。

完整 Buildroot 编译内核、DTB 和包；发布 inspector 必须证明 DTB 没有 `ubi_kernel`，
且 rootfs/cfg_bak 与已验证 MIBIB 一致。BDF 暂不修改，HE160 仍是独立实验项。

dashboard 和 CI 只能证明配置/构建事实，不能证明真实 WAN、射频、secure boot 或救援。
因此 company.2-rc2 明确 RC-only，stable 由生产 evidence 文件阻断。stable evidence 的
文件 SHA、opaque hardware/serial record IDs 与精确固件 SHA 同时进入签名 v2 manifest；
RC 不能继承或硬编码 VERIFIED。
