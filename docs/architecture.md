# 架构与可信边界

1. **官方固件层**：OpenWrt 25.12.5、`qualcommax/ipq807x`、`xiaomi_ax9000`、标准分区、
   firewall4/nftables、LuCI SSL、中文与两个官方救援主题。
2. **策略计划层**：命名 `unicom`/`mobile` interface、独立 REJECT uplink zones 和 pbr
   policies；生成器只输出 incremental staging plan，绝不整包 import/live apply。
3. **企业基础能力**：WireGuard、logd、轻量 collectd 预装但无机密/collector；SQM mobile
   可选；OpenClash 仅依赖。PBR/OpenClash/手工 nft 必须单一 mark/table/chain owner。
4. **overlay 管理层**：CompanyWrt LuCI、脚本、模板、首启 redirect。当前通过 FILES
   overlay 安装并在 manifest/SBOM/NOTICE 标为 `overlay-not-apk`；Makefile 不等于 APK。
5. **发布信任层**：固定 ImageBuilder、解包内容检查、严格 usign manifest、SIZE/SHA、
   annotated tag=protected main、`firmware-signing` environment、tag ruleset、GitHub
   immutable release/attestation、最小权限 job、RC prerelease 与 stable 真机证据门禁。

ImageBuilder 只重组官方 binary packages。需要 DTS/分区/kernel/BDF 修改时必须先提交
救援/回滚设计，再进入独立 Buildroot；不能用 overlay 伪装硬件支持。

dashboard 和 CI 只能证明配置/构建事实，不能证明真实 WAN、射频、secure boot 或救援。
因此 company.2-rc2 明确 RC-only，stable 由生产 evidence 文件阻断。stable evidence 的
文件 SHA、opaque hardware/serial record IDs 与精确固件 SHA 同时进入签名 v2 manifest；
RC 不能继承或硬编码 VERIFIED。
