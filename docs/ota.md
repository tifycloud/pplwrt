# OTA、人工确认与发布

CI 发布 `VERSION`、profile、镜像文件、`RELEASE-MANIFEST`、`manifest` 和 `SHA256SUMS`。`ota-check.sh` 只下载/解析 manifest 并核对 `VERSION/PROFILE/IMAGE/SHA256`，不写设备；`ota-apply.sh` 需要 root、镜像文件、`sysupgrade -T` 和 `--confirm VERSION`，升级前备份 network/firewall/pbr/wireless/company 与日志。

发布流程：

1. stable 构建完成，核对官方 ImageBuilder SHA、profile、包 manifest、测试矩阵和 git tag。
2. 发布者在 GitHub release 中上传 artifacts，说明官方源、构建 commit、已知限制和回滚路径；私密日志/配置不上传。
3. 管理员离线下载并校验 SHA256，先在一台 AX9000 做有线/救援/业务回归。
4. 管理员明确确认版本后，运行 `ota-apply.sh` 的测试；复核备份后手工执行实际 `sysupgrade`。失败时按救援文档回退，不自动循环重试。

Beta 与 HE160/BDF workaround 只能放 beta 目录/release，必须明确不可用于生产。
