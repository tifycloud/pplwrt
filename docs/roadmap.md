# Roadmap

## 当前：25.12.5-company.2-rc1（仅 RC）

- 固定 official ImageBuilder/profile/SHA；版本化输出与 squashfs 内容检查。
- plan-only 双 WAN/PBR；严格 signed OTA；安全首启/preflight；动态只读 UI。
- WireGuard/logd/collectd 基础、mobile SQM 可选模板、overlay SBOM/NOTICE。
- 最小权限 release pipeline、Sigstore attestation、RC prerelease/stable production gate。

## 进入 stable 前（全部需要真实 AX9000）

- 确认中国/国际硬件变体、secure boot、MTD、boot slot 与官方恢复路径。
- factory/initramfs/sysupgrade、断电、救援、配置恢复演练。
- HE80/监管域/BDF、双 WAN/IPv6/VLAN/WireGuard/PBR/OpenClash/SQM/OTA 完整矩阵。
- 生成脱敏 evidence bundle hashes 和命名人工审批；通过 production-gates schema。

## 后续工程

- 用同版本 official OpenWrt SDK 单独构建/签署两个 CompanyWrt APK，并由 ImageBuilder 安装；
  完成前继续诚实使用 overlay 名称，不为包构建切换完整 Buildroot。
- 设计 staged key rotation、回滚版本策略、集中日志 TLS/collector 与监控告警。
- 只有 DTS/分区/kernel/BDF/启动链确需修改时建立独立 Buildroot 分支和救援门禁。
