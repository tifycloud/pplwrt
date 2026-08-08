# Xiaomi AX9000 “暗云 boot 大分区”与 OpenWrt 25.12.5 兼容性

研究与真机只读复核日期：2026-08-08。没有执行镜像、修改 UCI/Bootloader 或写入任何
MTD/UBI；唯一的路由器端输出是 `/tmp` 下的临时、脱敏预检结果。

## 结论

**官方/标准 OpenWrt 25.12.5 AX9000 镜像仍然禁止刷写。真机已经通过仓库的暗云
单 UBI 指纹预检，因此项目选择“保留现有 MIBIB/U-Boot，完整 Buildroot 定制 DTS 和
单 UBI 升级路径”。只有专属 `xiaomi_ax9000_darkyun`、签名与内容门禁全部通过的 RC
才可进入一次受控首刷；它在真机启动、回滚和网络矩阵验证前仍不等于生产 stable。**

原因不是镜像型号不对，而是两套存储语义不同：

- 给定 `ax9000-mibib.bin` 定义一个从 `0x01180000` 开始、长 232 MiB 的单一
  `rootfs`，没有 `ubi_kernel`。
- 官方 25.12.5 内核故意忽略 Bootloader/SMEM 注入的分区表，在同一物理区域固定切成
  56 MiB `ubi_kernel` 和 182.5 MiB `rootfs` 两个独立 UBI MTD。
- 官方 sysupgrade tar 也按这两个独立 UBI 写 kernel/root。它不是“大分区自适应”镜像。
- 给定 U-Boot 的字符串与公开 QSDK 同源代码都表明 `bootipq` 会按 SMEM/MIBIB 的
  `rootfs.offset` 和 `rootfs.size` 建一个临时 `fs` 分区，再从其中的 UBI `kernel`
  volume 启动。若它实际扫描完整 232 MiB，大分区中同时存在两个独立 UBI 会与这一
  启动模型冲突。没有该“暗云 boot”的精确源码、发布说明或真机串口启动日志，不能
  假定它暗中把扫描范围截成官方所需的 56 MiB。
- 一次迁移实际使用的是**当前 kwrt** 中的 `sysupgrade`。真机已确认支持 `-T` 和 `-F`，
  但仓库仍以独立首刷包装器强制执行 MIBIB/APPSBL、MTD/UBI、签名、SHA256、profile、
  board 和嵌入 DTB 门禁；包装器只打印最终命令，不自动刷写。

给定 MIBIB 与官方 DTS 在 `0x01180000` 之前的 boot chain/ART 区域基本对齐；官方
代码不会主动写 MIBIB、APPSBL 或 ART，但会改 `0:APPSBLENV` 中的启动变量，并会把
官方 `rootfs` UBI 延伸到 NAND 末尾，因而**有意覆盖 MIBIB 所称的末端 `cfg_bak`**。
这不是随机写错数字 MTD，而是两套分区语义重叠，仍然足以导致不可启动或破坏原恢复布局。

## 一手源码：官方 25.12.5 实际期望

### 内核 DTS 是固定 split-UBI，不采用 MIBIB 的 rootfs 边界

官方 DTS 解释了其设计：Bootloader 会从 SMEM 表向 NAND 节点注入 legacy
partitions，所以 OpenWrt 放置一个 disabled dummy node，再由 `nand@0` 下的
`fixed-partitions` 决定内核看到的布局。关键固定分区为：

| 内核 MTD | 起点 | 长度 | 结束 | 含义 |
|---|---:|---:|---:|---|
| `ubi_kernel` | `0x01180000` | `0x03800000`（56 MiB） | `0x04980000` | 独立 kernel UBI |
| `rootfs` | `0x04980000` | `0x0b680000`（182.5 MiB） | `0x10000000` | 独立 root/rootfs_data UBI |

来源：[OpenWrt v25.12.5 `ipq8072-ax9000.dts`，禁用 SMEM 注入说明及固定分区](https://github.com/openwrt/openwrt/blob/v25.12.5/target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq8072-ax9000.dts#L143-L326)，
源码路径 `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq8072-ax9000.dts:143`、`:318`。

官方设备页记录的 OEM/标准过渡布局则是：`rootfs` 56 MiB、`rootfs_1` 56 MiB、
`cfg_bak` 1 MiB、`overlay` 125.5 MiB。其第一个 56 MiB `rootfs`
`0x01180000-0x04980000` 恰好与官方 DTS 的 `ubi_kernel` 对齐；官方 DTS 再把
`rootfs_1 + cfg_bak + overlay` 的整个后半段重解释为新的 `rootfs`。这解释了官方流程
为什么能让 Bootloader 只在 56 MiB 范围找 kernel，而让 Linux 使用余下空间。来源：
[官方设备页 OEM/QSDK flash layout](https://openwrt.org/toh/xiaomi/ax9000#flash_layout_in_oem_firmware) 及
[初始支持 commit 的安装与 unified-rootfs 说明](https://github.com/openwrt/openwrt/commit/2ddb2057cdf4a08fd2abb8c09d02e28a2d14f406)。给定大分区
MIBIB 把上述四段合并成 232 MiB `rootfs`，正是关键差异。

设备 recipe 固定 NAND eraseblock 128 KiB、page 2048 B、kernel 区 57344 KiB，并启用
`Device/UbiFit`。`UbiFit` 生成 `factory.ubi`；默认 sysupgrade 是带 metadata 的 tar。
来源：[AX9000 recipe](https://github.com/openwrt/openwrt/blob/v25.12.5/target/linux/qualcommax/image/ipq807x.mk#L475-L494)、
[qualcommax image 公共 recipe](https://github.com/openwrt/openwrt/blob/v25.12.5/target/linux/qualcommax/image/Makefile#L4-L37)。

### 官方 sysupgrade 明确写两个 UBI

AX9000 分支先写 U-Boot env，强制单系统启动，然后设置：

```sh
CI_KERN_UBIPART="ubi_kernel"
CI_ROOT_UBIPART="rootfs"
nand_do_upgrade "$1"
```

来源：[v25.12.5 `platform.sh:241-258`](https://github.com/openwrt/openwrt/blob/v25.12.5/target/linux/qualcommax/ipq807x/base-files/lib/upgrade/platform.sh#L241-L258)。
如果正在 initramfs/tmpfs 中迁移，pre-upgrade 还要求两个 MTD 名称都存在并分别
`ubiformat`；见同一文件的
[`xiaomi_initramfs_prepare():7-30`](https://github.com/openwrt/openwrt/blob/v25.12.5/target/linux/qualcommax/ipq807x/base-files/lib/upgrade/platform.sh#L7-L30)。

通用 NAND 升级代码按名称查找 MTD；找不到会报
`cannot find ubi mtd partition ...`。当 kernel/root 分处两个 UBI 时，它分别 attach
`CI_KERN_UBIPART` 和 `CI_ROOT_UBIPART`，创建 volume 后写入 tar 中的 kernel/root。
来源：[v25.12.5 `nand.sh:122-203`](https://github.com/openwrt/openwrt/blob/v25.12.5/package/base-files/files/lib/upgrade/nand.sh#L122-L203) 和
[`nand.sh:311-367`](https://github.com/openwrt/openwrt/blob/v25.12.5/package/base-files/files/lib/upgrade/nand.sh#L311-L367)。

这说明：

- 若**当前运行内核**只有一个 232 MiB `rootfs` 且没有 `ubi_kernel`，官方这版脚本会在
  找 `ubi_kernel` 时失败；但第三方 kwrt 可能带不同脚本，不能据此承诺“安全失败”。
- 即使第三方脚本把官方 tar 的 kernel/root 写成同一个大 UBI，重启后的官方 kernel
  仍按 DTS 查找物理 `0x01180000`/`0x04980000` 两个 UBI，布局仍不匹配。
- 官方 `platform_check_image()` 本身直接 `return 0`，metadata/profile 检查不验证 MTD
  几何；因此 `sysupgrade -T` 是必要条件但绝不是分区兼容证明。来源：
  [`platform.sh:149-151`](https://github.com/openwrt/openwrt/blob/v25.12.5/target/linux/qualcommax/ipq807x/base-files/lib/upgrade/platform.sh#L149-L151)。

## 两个用户提供的 binary

### 文件身份与散列

| 文件 | 大小 | `file` | SHA-256 | MD5 |
|---|---:|---|---|---|
| `ax9000-mibib.bin` | 262144 B (`0x40000`) | `data` | `2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11` | `7332a1d396eb4c532ae5780f4072433f` |
| `uboot-xiaomi-ax9000.bin` | 653422 B (`0x9f86e`) | ELF32 little-endian ARM, EABI5, statically linked/shared-object form | `80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007` | `a81be2ac8775bcb3f13870352ad46155` |

真机只读预检已确认：`0:mibib` 前 262144 B 与给定 MIBIB 散列一致，`0:appsbl` 和
`0:appsbl_1` 前 653422 B 都与给定 U-Boot 散列一致。因此这两个散列现在同时是下载文件
身份和本机当前 Bootloader 链的强制迁移指纹。

### MIBIB v4 解析

文件在 `0x800` 和 `0x20800` 各有一份字节完全一致的 Qualcomm SMEM partition table：
magic `0x55ee73aa/0xe35ebddb`、version 4、23 entries。Linux 的一手 parser 定义 entry
为 16-byte name + little-endian block offset/length，并乘 NAND erasesize；来源：
[Linux `drivers/mtd/parsers/qcomsmempart.c`](https://github.com/torvalds/linux/blob/v6.12/drivers/mtd/parsers/qcomsmempart.c#L18-L55) 及
[换算逻辑](https://github.com/torvalds/linux/blob/v6.12/drivers/mtd/parsers/qcomsmempart.c#L137-L151)。
按 AX9000 的 128 KiB erasesize 解析，关键尾部为：

| MIBIB name | block offset/length | byte range | 大小 |
|---|---:|---:|---:|
| `crash` | `0x84 / 0x4` | `0x01080000-0x01100000` | 0.5 MiB |
| `crash_syslog` | `0x88 / 0x4` | `0x01100000-0x01180000` | 0.5 MiB |
| `rootfs` | `0x8c / 0x740` | `0x01180000-0x0f980000` | **232 MiB** |
| `cfg_bak` | `0x7cc / 0x4` | `0x0f980000-0x0fa00000` | 0.5 MiB |
| 未分配 | — | `0x0fa00000-0x10000000` | 6 MiB |

`0:SBL1`、`0:MIBIB`、BOOTCONFIG/QSEE/DEVCFG/APDP/RPM/CDT 双份、
`0:APPSBLENV`、APPSBL 双份、`0:ART`、`bdata` 均位于 `0x01180000` 之前，
其 offset/size 与官方 DTS 的 boot-chain 区域一致。实质分歧从 `0x01180000` 开始：

```text
给定 MIBIB:  0x01180000 [---------------- rootfs 232 MiB ----------------] cfg_bak  (到 250 MiB)
官方 DTS:    0x01180000 [ubi_kernel 56 MiB] [------- rootfs 182.5 MiB -------] (到 256 MiB)
```

因此官方 DTS 的 `rootfs` 会覆盖大分区 `rootfs` 的后半段、`cfg_bak` 和末尾未分配区；
它并不改写 `0x01180000` 之前的 MIBIB/APPSBL/ART。

### `strings` / `binwalk` 结果与来源缺口

使用 Binwalk 3.1.0 只读扫描：

- MIBIB 没有命中通用嵌入格式 signature；这不否定上面按 Qualcomm 结构解析出的表。
- U-Boot 命中 ELF32 ARM、SHA-256 constants、两组 CRC32 tables，以及从 `0x84230`
  到 `0x92900` 的 18 个内嵌 DTB；其中字符串含 `config@hk14`。
- ELF entry 为 `0x4a900000`，load segment 从文件 `0x12000` 映射到 `0x4a900000`。
- 可打印字符串含 `U-Boot 2016.01 (Jan 10 2023 - 11:26:06 +0800)`、Web UI
  `uboot2.0 version:23.01.10`、`bootcmd=bootipq`、
  `ubi.mtd=rootfs root=mtd:ubi_rootfs rootfstype=squashfs`，以及：

```text
setenv mtdparts mtdparts=nand0:0x%llx@0x%llx(fs),${msmparts} &&
ubi part fs && ubi read ... kernel
```

这与公开的 QSDK/GL.iNet `cmd_bootqca.c` 同源路径一致：代码用
`sfi->rootfs.size`/`offset` 创建 `fs` 再 `ubi part fs`、读取 `kernel`；参见
[GL.iNet 固定 commit 的 `cmd_bootqca.c:679-698`](https://github.com/gl-inet/uboot-ipq60xx/blob/f42cd52a9d7f52f4fa7252df17c544205065a018/board/qca/arm/common/cmd_bootqca.c#L679-L698)。
这是**代码族佐证/推断**，不是给定 binary 的可复现源码证明。

Web 页面字符串把 UI 项目链接到
[`pepe2k/u-boot_mod`](https://github.com/pepe2k/u-boot_mod)，但该官方仓库自述为
“U-Boot 1.1.4 modification for routers”，已归档，公开 release 是 2013/2014；它不是
这份 2023 年 U-Boot 2016.01 AX9000 binary 的精确源码或发布页。

在精确文件名、SHA-256、版本字符串和公开代码/发布记录中未找到可验证的“暗云 boot”
作者仓库、release notes、构建 commit、签名或这两个文件的官方 checksum。故目前不知道：

- Web “firmware update” 究竟写 `rootfs` 的哪个物理 offset/length；
- 是否强制把 boot 扫描范围从 MIBIB 的 232 MiB 截成 56 MiB；
- 是否接受 raw UBI、FIT、sysupgrade tar，是否会解析/剥离 ELF header；
- Web 更新器是否接受任意格式仍未知；本项目明确不使用该 Web 更新器。

在补齐这些证据前，**不得调用 U-Boot Web 的 firmware/uboot update，也不得用
`mtd write`、`nandwrite`、`ubiformat` 或 `fw_setenv` 试探。**

## factory、initramfs 与 sysupgrade 不是同一种东西

官方 25.12.5 下载目录和 `profiles.json` 列出四个 AX9000 产物；来源：
[官方目录](https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/)、
[profiles.json](https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/profiles.json)、
[sha256sums](https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/sha256sums)。

| 产物 | 容器/用途 | 与“大分区”关系 |
|---|---|---|
| `initramfs-uImage.itb` | RAM 启动 FIT kernel；不等于持久安装 | 适合受控的临时启动/采证，但如何让暗云 boot 加载仍需其官方流程或 UART/TFTP 证据 |
| `initramfs-factory.ubi` | 仅 release source build 生成的中间 UBI/initramfs；官方设备页用它写 stock 的非活动 56 MiB rootfs，再进 RAM 做迁移 | recipe 用 `ifeq ($(IB),)` 排除 ImageBuilder，标准 IB 不会生成；不能盲写 232 MiB rootfs |
| `squashfs-factory.ubi` | `append-ubi` 生成的 raw UBI；离线解析官方文件含 `kernel`、`rootfs`、autoresize `rootfs_data` volumes | 没有 sysupgrade tar/metadata；“factory”不代表任意 OEM/第三方 U-Boot Web 都认识。其 kernel 内仍是官方 split DTS |
| `squashfs-sysupgrade.bin` | tar + metadata；官方文件内含 `CONTROL`、5,394,956 B kernel FIT、10,019,840 B squashfs root | 当前系统脚本把两者写到 `ubi_kernel`/`rootfs`；不是给单一大 UBI 的 combined image |

官方 AX9000 页面当前安装流程仍是先把 initramfs factory UBI 写到经
`/proc/mtd` 核实的 stock 非活动 rootfs，再从临时 OpenWrt 执行完整 sysupgrade；来源：
[OpenWrt AX9000 设备页](https://openwrt.org/toh/xiaomi/ax9000) 和
[初始设备支持 commit 的安装说明](https://github.com/openwrt/openwrt/commit/2ddb2057cdf4a08fd2abb8c09d02e28a2d14f406)。
设备页是可变 wiki，且混有旧版/QSDK 章节；遇到冲突以 v25.12.5 源码为准。

`openwrt.ai`/kwrt 只记录为用户当前第三方来源。它的文件名或 UI 标签不能替代该 build
实际使用的 DTS、upgrade scripts、manifest 和 Bootloader 证据。

## 决策矩阵

| 已证实的真机状态 | 官方 standard sysupgrade | 官方 factory/initramfs | 决策 |
|---|---|---|---|
| 当前 `/proc/mtd` 精确为 `ubi_kernel` 56 MiB + `rootfs` 182.5 MiB；live DT 与官方地址一致；当前 upgrade scripts 是官方 split 路径；串口证明 U-Boot 只扫描前 56 MiB kernel UBI；救援已实测 | **可在维护窗口考虑**；仍需 hash、`sysupgrade -T`、备份和串口 | 不需要 factory | **可直接 sysupgrade** |
| 当前为一个 `rootfs` 232 MiB，Bootloader 也按一个大 UBI 读取 kernel/root | **不可用**；目标 kernel 的 split DTS 与大 UBI 冲突 | 官方 raw factory 也不能因名称相同就刷 | **需定制 DTS + OpenWrt Buildroot/source build**：保留 `0x01180000+0x0e800000` 单一 UBI，并配套单 UBI upgrade script；ImageBuilder 仅换包不够 |
| 要回到官方 standard，而真机仍使用这份 232 MiB MIBIB | 先不刷 | 先不刷 | **必须先恢复经本机/批次验证的标准分区与 56 MiB boot 扫描边界**，再按官方 initramfs→sysupgrade 流程；这是高风险 MIBIB 操作，只能在 UART/TFTP/完整备份可恢复条件下做。给定 `ax9000-mibib.bin` 本身是大分区文件，不是标准恢复文件 |
| 当前 MTD、live DT、当前脚本、installed MIBIB/U-Boot hash 任一未知/不一致 | **禁止** | **禁止** | **证据不足禁止刷** |

本机属于第二行：预检确认 `rootfs=mtd21`、`0x0e800000`、eraseblock `0x20000`，没有
`ubi_kernel`，一个 UBI 内仅有 `kernel/rootfs/rootfs_data`；MIBIB 与两个 APPSBL 副本
也都匹配。当前 KWRT 的 `/sbin/sysupgrade`、`platform.sh` 和 `nand.sh` 也已固定 SHA256；
一次迁移预检会拒绝任何脚本变化，避免升级 KWRT 后仍沿用旧放行结论。因此仓库不会
尝试恢复标准分区，而是只构建专属单 UBI sysupgrade。

“定制 DTS”与“恢复标准分区”是二选一的存储模型，不能只改镜像文件名或只替换一个
`platform.sh`。前者必须让 Bootloader、live DTS、factory 格式和后续 sysupgrade 始终
使用同一个大 UBI；后者必须让 Bootloader 的 kernel UBI 扫描边界与官方 56 MiB 匹配。

## 真机只读采证清单

以下命令不写 flash/env；请通过有线 SSH 保存完整输出，脱敏 MAC、序列号、公网地址、
密码/密钥。**不要同时执行任何含 `set`、`erase`、`format`、`write`、`upgrade` 的命令。**

### 1. 身份、版本和启动参数

```sh
date -u
uname -a
ubus call system board
cat /etc/openwrt_release
cat /tmp/sysinfo/board_name 2>/dev/null
cat /proc/cmdline
cat /proc/partitions
cat /proc/mtd
```

必须看到真实 `board_name`、target、kernel、kwrt/OpenWrt revision，以及 cmdline 中的
`ubi.mtd=`/root 参数。`/proc/mtd` 名称和 size 比 mtd 编号重要，编号会随 DTS 改变。

### 2. live DT 与物理 MTD 枚举

```sh
tr -d '\000' </sys/firmware/devicetree/base/model; echo
tr '\000' '\n' </sys/firmware/devicetree/base/compatible
sha256sum /sys/firmware/fdt 2>/dev/null
command -v dtc >/dev/null && dtc -I dtb -O dts /sys/firmware/fdt

for d in /sys/class/mtd/mtd[0-9]*; do
    echo "$d"
    cat "$d/name" "$d/size" "$d/erasesize"
    test ! -r "$d/offset" || cat "$d/offset"
done

dmesg | grep -Ei 'nand|mtd|partition|ubi|ubiblock|squashfs|ubifs|bad block'
```

需要从 DTS/dmesg 取得地址范围，而不只是 `/proc/mtd` 的 size。放行官方布局所需的精确
证据是 `ubi_kernel 0x01180000-0x04980000` 和
`rootfs 0x04980000-0x10000000`。

### 3. UBI volumes、根文件系统和 overlay

```sh
ubinfo -a
for u in /sys/class/ubi/ubi[0-9]*; do
    echo "$u"
    cat "$u/mtd_num" "$u/dev" 2>/dev/null
done
for v in /sys/class/ubi/ubi[0-9]_*; do
    echo "$v"
    cat "$v/name" "$v/type" "$v/data_bytes" 2>/dev/null
done
cat /proc/mounts
findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS / /overlay 2>/dev/null
df -hT / /overlay
ls -ld /overlay
```

这能区分“kernel/rootfs 两个 UBI device”和“一个大 UBI 内多个 volume”；两者名称可能
相似，但不能互换。

### 4. 当前升级实现（决定 direct sysupgrade 实际会做什么）

```sh
sha256sum /sbin/sysupgrade /lib/upgrade/platform.sh /lib/upgrade/nand.sh 2>/dev/null
sed -n '1,340p' /lib/upgrade/platform.sh
sed -n '1,560p' /lib/upgrade/nand.sh
grep -RnsE 'xiaomi,ax9000|ubi_kernel|CI_(KERN|ROOT|UBI)PART|nand_do_upgrade' \
    /lib/upgrade /sbin/sysupgrade 2>/dev/null
```

若已下载并按官方 `sha256sums` 验证 25.12.5 sysupgrade，可额外只做：

```sh
sysupgrade -T /tmp/openwrt-25.12.5-qualcommax-ipq807x-xiaomi_ax9000-squashfs-sysupgrade.bin
echo "$?"
```

不要省略：`-T` 成功只证明当前 checker 接受容器/profile，不证明写入边界或重启可启动。

### 5. Boot environment（只读）

```sh
cat /etc/fw_env.config 2>/dev/null
command -v fw_printenv
fw_printenv 2>&1
```

重点保存 `bootcmd`、`bootargs`、`fsbootargs`、`mtdparts`、`flag_boot_rootfs`、
`flag_last_success`、`flag_boot_success`、`boot_wait`、`uart_en`、`rootfs_data_max`。
`fw_printenv` 若报 CRC/config 错误就标记为不可信，**不要用 `fw_setenv` 修复或试写**。

### 6. 最关键的 Bootloader 边界证据

还需要一次正常冷启动的完整 UART log（从 U-Boot banner 到 Linux MTD/UBI attach 完成），
以及当前烧录 MIBIB/APPSBL 的只读 dump/hash。先由熟悉 NAND/ECC 的管理员依据
`/proc/mtd` 名称制定 dump 命令，不要猜 `/dev/mtdN`。

串口日志必须回答：

- U-Boot banner/build/hash 是否与给定 binary 一致；secure boot 是否启用；
- `bootipq` 选择的 rootfs offset/size 是 56 MiB 还是 232 MiB；
- `ubi part fs` attach 的 MTD size、image sequence、volume list；
- 是否有两个 UBI image/sequence 冲突、fallback slot 或认证失败；
- Linux 随后创建的 MTD 地址是否与官方 fixed DTS 一致。

完整 UART 日志仍是恢复演练和 stable 放行的重要证据，但不再用缺失的暗云作者源码替代
真机已测指纹。首次 RC 刷写必须在有线维护窗口、备份和可用串口/Bootloader 救援条件下
进行；真机启动证据会回填 production gate，之后才能发布 stable。

## 证据等级与剩余风险

- **高置信**：官方 v25.12.5 DTS、image recipe、platform/nand upgrade 源码；官方 release
  目录、profiles 和 hashes；给定 MIBIB 的结构化离线解析。
- **中置信**：给定 U-Boot 的静态 strings/binwalk 与公开 QSDK 同源 boot path 的匹配。
- **高置信（真机）**：当前单 `rootfs` MTD 几何、UBI volume 集、boot root、MIBIB 与两个
  APPSBL 副本指纹，以及当前 `sysupgrade -T/-F` 选项；均由只读预检取得。
- **未知/RC 风险**：暗云作者与精确源码、Web updater 行为、secure boot 细节和完整恢复
  演练；项目不依赖 Web updater，剩余风险必须靠受控首刷和串口/启动证据关闭。

因此当前可审核决策是：**标准镜像永久拒绝；完整定制大分区 Buildroot 路线已经获得真机
前置证据。待专属 RC 的真实编译、DTB/rootfs/签名/attestation 检查全部通过后，可交付用户
进行一次受控首刷；首刷成功和硬件矩阵未回填前，不发布 production stable。**
