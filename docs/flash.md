# AX9000 刷机、secure boot 与救援（管理员确认）

错误型号/区域变体/分区/启动槽或断电会变砖。本仓库没有看到用户实机标签、secure boot、
bootloader 或 MTD 证据，因此 **不能判断中国版还是国际版，也不能批准从 kwrt 直接
sysupgrade**。先完成下面的只读采集并由熟悉该硬件的管理员评审。

## 中国/国际变体与 secure boot

中国大陆和国际销售渠道可能使用不同 SKU、OEM 固件/监管域/恢复包；不同生产批次的
bootloader 签名策略或已解锁状态也可能不同。不要用 LuCI 语言、包装颜色、购买地区或
“别人同型号成功”推断 secure boot。以底壳完整型号/区域标识、bootloader/串口输出、
当前 OEM/第三方迁移记录和对应区域官方恢复流程为准。

权威入口（链接内容可能更新，必须搜索精确型号/区域）：

- OpenWrt AX9000 设备页：<https://openwrt.org/toh/xiaomi/ax9000>
- OpenWrt sysupgrade 通用流程：<https://openwrt.org/docs/guide-user/installation/generic.sysupgrade>
- 小米中国官方服务：<https://www.mi.com/service/>
- Xiaomi 国际官方支持：<https://www.mi.com/global/support/>

如果区域官方页面没有明确列出本机完整型号/恢复包，停止；不要混刷另一地区 OEM 包。
本项目不会绕过 secure boot，也不会提供未经官方/设备页验证的解锁命令。

## 当前 kwrt 设备必须先采集

在不写 flash/env 的前提下保存并脱敏：

```sh
ubus call system board
cat /proc/cmdline
cat /proc/mtd
mount
df -h
command -v fw_printenv && fw_printenv
```

还要记录当前 kwrt 精确版本/来源/hash、`sysupgrade -l` 备份范围、DSA/网络、无线校准/BDF
来源、active/fallback boot slot、厂商恢复/串口是否实测。`fw_printenv` 只有在已正确配置
env layout 时才可信；**不要运行 `fw_setenv`**。不得公开 MAC、serial、密钥或原始备份。

第三方 kwrt 可能改变分区/slot/升级脚本。必须将 `/proc/mtd`、cmdline、boot env 与
OpenWrt AX9000 官方设备页/镜像流程逐项比对；有任何差异就先走 initramfs/串口评审，
而不是把标准 sysupgrade 当作兼容证明。

## 候选镜像门禁

1. 离线备份配置、校准/BDF、SSH host keys、MTD/boot env 和救援证据；稳定电源/UPS。
2. 验证 GitHub attestation、usign manifest、实际 SIZE/SHA、VERSION/profile/board/channel。
3. `sysupgrade -T <verified-sysupgrade.bin>` 必须通过；这仍不证明分区/secure boot 兼容。
4. 首次迁移按 OpenWrt AX9000 页面匹配本机状态选择官方 initramfs/factory 路径；不要猜。
5. 只在本地有线、串口/官方恢复可用的窗口人工刷写。RC 先单机；严禁远程/Wi-Fi 刷写。
6. 启动后验证 enrollment、救援、断电、HE80、双 WAN、IPv6、VLAN、WG、PBR、
   OpenClash 和 OTA。全部证据进入 production gate 后才能考虑 stable。

`ota-apply` 只重复绑定校验并运行 `sysupgrade -T`，最终命令仅打印，不自动执行。
