# AX9000 刷机、secure boot 与救援（管理员确认）

错误型号、分区、启动链或断电会变砖。当前实机已完成只读采证：运行 KWRT 23.05.5，
MIBIB 与用户提供的 `ax9000-mibib.bin` 匹配，两个 APPSBL 与
`uboot-xiaomi-ax9000.bin` 匹配；内核只看到从 `0x01180000` 开始、大小 232 MiB 的
`rootfs` MTD，其 UBI 卷为 `kernel/rootfs/rootfs_data`。因此官方标准 AX9000 的
`ubi_kernel + rootfs` 双 UBI 镜像和历史 CompanyWrt 标准版都 **禁止刷入**。

仓库专属 `xiaomi_ax9000_darkyun` 镜像保留现有 MIBIB/U-Boot，不改 bootloader，内核 DT
和 `nand_do_upgrade` 都使用同一个 `rootfs` UBI。它仍然只能先作为 RC：没有完成本页的
实机启动、救援、断电和企业网络矩阵前，不批准生产刷写。

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

## 当前 kwrt 设备的只读指纹门禁

先读 [ax9000-partition-compatibility.md](ax9000-partition-compatibility.md)。通用采集器用于
保存审计记录：

```sh
chmod 700 /tmp/collect-device-layout.sh
/tmp/collect-device-layout.sh
```

输出位于 `/tmp/companywrt-device-layout.txt`。先检查并脱敏，再交给维护者。默认不读取
U-Boot environment；只有确认 `/etc/fw_env.config` 与本机 Bootloader 完全匹配后，才用
`--include-bootenv` 再采集。脚本不会执行 flash/env/UCI/MTD 写入。

也可以在不写 flash/env 的前提下手工保存并脱敏：

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

专属一次迁移门禁还必须在路由器上运行：

```sh
chmod 700 /tmp/ax9000-darkyun-preflight
/tmp/ax9000-darkyun-preflight --output /tmp/companywrt-darkyun-preflight.env
```

它只读取 MIBIB、两份 APPSBL、当前 `sysupgrade/platform/nand` 脚本、`/proc/mtd`、
cmdline 和 UBI sysfs；Bootloader/升级栈指纹、232 MiB rootfs、cfg_bak、擦除块及三个
UBI 卷必须全部吻合。输出 `RESULT=PASS` 仍只代表
“硬件布局属于这个迁移目标”，不代表候选镜像已获准刷入。脚本不执行 flash、env、UCI、
sysupgrade 或重启。

## 候选镜像门禁

1. 离线备份配置、校准/BDF、SSH host keys、MTD/boot env 和救援证据；稳定电源/UPS。
2. 验证 GitHub attestation、usign manifest、实际 SIZE/SHA、VERSION、
   `xiaomi_ax9000_darkyun`、`xiaomi,ax9000-darkyun` 和三项分区指纹。
3. 解包报告必须显示 `kernel_dtb_layout=PASS`；release 里不得出现 factory 镜像。
4. 当前 KWRT 只报告旧 board `xiaomi,ax9000`，所以普通 `sysupgrade -T` 应因设备身份不同而
   拒绝。一次迁移只能使用后续发布的专用人工迁移包装器：它再次检查上述指纹，再以
   force-test 方式验证镜像，并且最终刷机命令仍只打印、不执行。不要手工绕过该门禁。
5. 只在本地有线、串口/官方恢复可用的窗口人工刷写。RC 先单机；严禁远程/Wi-Fi 刷写。
6. 启动后验证 enrollment、救援、断电、HE80、双 WAN、IPv6、VLAN、WG、PBR、
   OpenClash 和 OTA。全部证据进入 production gate 后才能考虑 stable。

`ota-apply` 只用于已经运行 `xiaomi,ax9000-darkyun` 的后续升级；它重复绑定校验并运行
`sysupgrade -T`，最终命令仅打印，不自动执行。第一次从 KWRT 迁移不能拿 OTA 脚本代替
专属迁移门禁。
