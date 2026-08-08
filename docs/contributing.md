# 贡献指南

提交前运行 `./scripts/verify-shell.sh`、`tests/ax9000/test-profile.sh` 和 `tests/ax9000/test-network-generator.sh`。改动网络、PBR、无线、OTA 或安全边界时，更新架构/安全/测试矩阵和 CHANGELOG；添加新包时说明官方 feed、版本、许可证、大小、依赖和回滚。

提交信息建议使用 `area: change`，PR 必须包含构建 release、manifest/SHA、目标 profile、实机/容器测试环境和未完成项。严禁提交密钥、订阅、生产日志、配置备份、完整 ImageBuilder tarball 或未经授权的 GitHub remote。维护者在合并前独立复核构建与安全敏感改动。
