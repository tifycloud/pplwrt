# 刷机与救援（管理员确认）

AX9000 是真实硬件，错误型号/分区/中断刷写可能变砖。先确认底壳型号、序列号、电源稳定、网线直连和救援路径；不要通过 Wi-Fi、远程跳板或无 UPS 的链路刷写。

1. 下载官方 initramfs factory、factory UBI 或 sysupgrade 文件，并按 `devices/ax9000/profile.json` 与官方 `sha256sums` 校验。
2. 备份 `/etc/config`、无线校准/BDF、SSH host key、日志和当前分区信息到离线介质；确认能进入官方恢复/串口。
3. **管理员确认**：确认 `xiaomi,ax9000`、25.12.5、目标文件类型与标准分区一致，记录操作者和时间。
4. 首次迁移优先使用官方文档规定的 initramfs/factory 路径验证启动，再从 LuCI/SSH 使用同型号 squashfs-sysupgrade；不要将 AX3600 镜像或第三方分区表用于 AX9000。
5. 启动后只通过有线 LAN 验证 LuCI、SSH、`ubus call system board`、存储、两个无线频段和救援入口。失败时停止反复刷写，回到已验证的 initramfs/串口救援。

`scripts/ota-apply.sh` 只执行 `sysupgrade -T` 校验，不会替管理员自动重启；实际 `sysupgrade` 命令需在复核备份与 manifest 后手工执行。
