# Changelog

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
