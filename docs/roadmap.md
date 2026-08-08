# Roadmap

## 当前：25.12.5-company.2-rc3（仅 RC）

- 固定官方 OpenWrt/feeds/patch；暗云单 UBI profile、FIT DTB/squashfs 内容检查。
- plan-only 双 WAN/PBR；严格 signed OTA；安全首启/preflight；动态只读 UI。
- WireGuard/logd/collectd 基础、mobile SQM 可选模板、overlay SBOM/NOTICE。
- exact-main annotated tag、受保护签名 environment、immutable release/attestation、RC
  prerelease/stable production gate；RC2 完成旧→新 usign 过渡，RC3 仅用当前 key 主签。

## 进入 stable 前（全部需要真实 AX9000）

- 已确认该实机 MIBIB/APPSBL/MTD/UBI 指纹；仍需 UART/暗云 Boot 救援与冷启动证据。
- 专属 sysupgrade、断电、救援、配置恢复演练；factory 明确不生成/不发布。
- HE80/监管域/BDF、双 WAN/IPv6/VLAN/WireGuard/PBR/OpenClash/SQM/OTA 完整矩阵。
- 生成脱敏 evidence bundle hashes 和命名人工审批；通过 production-gates schema。

## 后续工程

- 用同版本 official OpenWrt SDK 单独构建/签署两个 CompanyWrt APK，并由 Buildroot 安装；
  完成前继续诚实使用 overlay 名称。
- 在下一次 key rotation 前设计独立的多阶段过渡版本；完善回滚版本策略、集中日志
  TLS/collector 与监控告警。
- 向上游整理暗云变体 patch 的可维护提交；BDF/HE160 仍独立于分区适配。
