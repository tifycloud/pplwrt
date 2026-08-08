# 贡献与发布规则

提交前运行：

```sh
./scripts/verify-shell.sh
for t in tests/ax9000/test-*.sh; do "$t"; done
actionlint .github/workflows/*.yml
```

网络、OTA、安全、包、UI 或构建改动必须同步更新测试、架构/安全/操作文档和 CHANGELOG。
新增 upstream package 要记录 official feed、版本、许可证、依赖/体积和启用/回滚边界，
并进入 package manifest/SBOM/NOTICE 内容检查。

禁止提交私钥、密码、token、订阅、生产配置/日志、serial/MAC、公网 IP、完整 ImageBuilder
archive 或未脱敏真机 evidence。公钥允许提交；私钥 secret 名固定但值永不输出。

tag 必须为 `v$(cat VERSION)`。RC/beta 只能 prerelease；stable 必须有对应
`production-gates/<VERSION>.env` 真机记录，模板不算证据。author 不得把 CI/build success
描述为硬件验收；发布后还要验证 release assets、usign、SHA、attestation 和 OTA 下载链。
