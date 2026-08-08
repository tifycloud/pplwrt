# CompanyWrt 全新安装教程（AX9000 暗云 Boot 大分区）

> 当前适用版本：`25.12.5-company.2-rc3`  
> 当前状态：已通过构建、签名、固件内容、分区指纹和刷前兼容性检查；**仍是 RC，不是企业稳定版**。  
> 适用设备：本项目已经采证的 Xiaomi AX9000，暗云 Boot 单 UBI 大分区布局。其他 AX9000 不得照抄。

本教程用于把已核验的 KWRT 设备**全新安装**为 CompanyWrt。刷写使用 `-n`，不会保留
KWRT 配置。教程不修改 MIBIB、U-Boot 或无线校准分区，也不使用 factory 镜像。

独立网页排版版见 [fresh-install.html](fresh-install.html)。刷机前还应阅读
[分区兼容性说明](ax9000-partition-compatibility.md)和[刷机与救援说明](flash.md)。

## 1. 先确认这份教程确实适用于你的设备

只有下列信息**全部一致**才允许继续：

| 项目 | 必须匹配的值 |
| --- | --- |
| 当前迁移来源 | KWRT，运行时 board 为 `xiaomi,ax9000` |
| MIBIB SHA256 | `2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11` |
| 两份 APPSBL SHA256 | `80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007` |
| NAND 布局 | `rootfs` 从 `0x01180000` 开始，大小 `0x0e800000`（232 MiB） |
| UBI 卷 | `kernel`、`rootfs`、`rootfs_data` 位于同一个 `rootfs` UBI |
| 目标 profile | `xiaomi_ax9000_darkyun` |
| 目标 board | `xiaomi,ax9000-darkyun` |
| 分区变体 | `darkyun-large-ubi-v1` |

本机此前已经通过专属只读门禁。**以下镜像一律禁止使用**：

- 官方标准 `xiaomi_ax9000` 镜像；
- 任何 `factory.ubi`；
- CompanyWrt `company.1`、RC1、RC2；
- OpenWrt.ai 页面中的 x86/64 镜像；
- 文件名、SHA256 或大小与本页不一致的镜像。

> **为什么会看到 board mismatch？** 当前 KWRT 报告 `xiaomi,ax9000`，新固件使用专属
> `xiaomi,ax9000-darkyun` 身份。普通兼容性测试拒绝是预期行为；只有专属门禁确认
> MIBIB、APPSBL、MTD、UBI 和升级脚本全部匹配后，才允许一次性使用 `-F` 迁移。

## 2. 维护窗口和救援准备

刷机前完成下面所有准备，不要在远程、无线或停电风险较高的环境操作。

1. 管理电脑用网线直连 AX9000 LAN，断开两条 WAN 和其他交换网络。
2. 使用稳定电源，最好接 UPS；准备至少 15 分钟无人触碰的维护窗口。
3. 确认暗云 U-Boot、串口或已验证的恢复方式可用，救援电脑和网线在手边。
4. 离线保存 KWRT 配置、SSH 主机密钥、校准/BDF、MTD/boot 环境采证和当前网络记录。
5. 备份只能用于人工参考；**不得把完整 KWRT 备份恢复到 CompanyWrt**。
6. 备份、订阅、密码和私钥不得提交到 Git 仓库或发送到公共聊天。

## 3. 下载唯一正确的 RC3 镜像

从 [CompanyWrt RC3 Release](https://github.com/tifycloud/pplwrt/releases/tag/v25.12.5-company.2-rc3)
下载：

```text
openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin
```

镜像的固定信息：

```text
大小：21371485 bytes
SHA256：577bd2f430c6128f40310ad7f939d613023e0f7b05f978997bddf4a4c536df87
```

macOS 校验：

```sh
shasum -a 256 openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin
```

Linux 校验：

```sh
sha256sum openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin
```

输出必须与上面的 64 位 SHA256 **逐字一致**。Release 中的 `SHA256SUMS`、
`RELEASE-MANIFEST`、`RELEASE-MANIFEST.sig` 和 GitHub attestation 也已经独立验证；不要只凭
文件名判断镜像。

## 4. 刷前门禁：当前这台路由器的状态

这台 AX9000 已经完成并通过：

- MIBIB、两份 APPSBL、MTD/UBI 和当前升级脚本指纹核对；
- RC3 manifest 的 usign 签名、下载大小和 SHA256 核对；
- profile、board、分区变体和来源版本绑定；
- `sysupgrade -T -F` **只测试不写入**；
- 专属内核 DTB 和单 UBI 升级路径的构建/内容检查。

如果路由器从门禁完成后**没有重启**，候选镜像当前位于：

```text
/tmp/companywrt-rc3-gate-7027353/ota/openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin
```

正式刷写前，在路由器上再核对一次：

```sh
sha256sum '/tmp/companywrt-rc3-gate-7027353/ota/openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin'
```

必须仍然得到：

```text
577bd2f430c6128f40310ad7f939d613023e0f7b05f978997bddf4a4c536df87
```

> **如果路由器已经重启，立即停止。** `/tmp` 是内存盘，重启后门禁结果和镜像都会消失。
> 不要仅重新上传镜像后手工使用 `-F`。必须重新运行完整的签名 + 硬件指纹 + 强制测试门禁。
> 当前 KWRT 没有内置 `usign`，因此应由维护者按已审计流程重新准备门禁环境；不得从未知
> KWRT 软件源随意安装工具，也不得跳过签名验证。

## 5. 执行全新安装

只有在以下条件同时满足时才执行：有线直连、救援可用、电源稳定、路由器未在门禁后重启、
路径存在、SHA256 正确，并且现场管理员明确同意刷写。

```sh
sysupgrade -n -F '/tmp/companywrt-rc3-gate-7027353/ota/openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin'
```

- `-n`：故意不保留 KWRT 配置，避免旧网络、插件和防火墙污染新系统。
- `-F`：只用于这次经过专属门禁的 board 身份迁移，不能用于普通升级。

按回车后不要关闭终端、不要再次执行命令、不要拔电、不要按 Reset。设备自动重启后至少等待
8–10 分钟。指示灯行为可能与 KWRT 不同，不要仅凭灯色判断失败。

## 6. 第一次连接和安全初始化

全新安装默认情况下使用 `192.168.1.1`。把电脑改为自动获取地址，重新插拔网线或更新 DHCP
租约；如果一个 LAN 口没有拿到地址，依次尝试其他 LAN 口，不要接 WAN。

访问：

```text
https://192.168.1.1/
```

首次是本地自签名 HTTPS 证书，浏览器可能警告。确认地址确实是直连路由器后再继续。也可以：

```sh
ssh root@192.168.1.1
```

第一件事是设置唯一、随机且离线保存的管理员密码：

```sh
passwd
```

随后运行 enrollment：

```sh
/usr/share/company/enrollment-preflight \
  --expected-version 25.12.5-company.2-rc3
```

再保存以下只读信息：

```sh
ubus call system board
cat /etc/companywrt/VERSION
cat /etc/companywrt/build.conf
cat /proc/mtd
ubinfo -a
```

预期结果应包含：

```text
25.12.5-company.2-rc3
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
```

任何 `FAIL`、board/profile/version 不一致或 UBI 异常都应停止接入生产网络，保留日志并进入
救援检查；不要继续配置双 WAN。

## 7. 推荐的首次配置顺序

1. 设置时区、NTP、管理密码和 HTTPS，导出第一次干净配置备份。
2. Wi-Fi 先使用 **HE80**；HE160 是 AX9000 专项测试项，不能作为首启默认值。
3. 先只连接联通宽带，确认 IPv4/IPv6、DNS、NAT 和 WAN 入站拒绝。
4. 再加入移动专线；联通作为办公/下载默认出口，移动用于服务器和指定稳定上传连接。
5. 逐个建立 management、office、server、iot、guest VLAN，并逐项验证隔离。
6. `company-network plan` 只生成待审阅计划，不会自动应用；确认端口、mark、table、DNS 和
   回滚方案后再人工落地。
7. 配置 WireGuard 管理、日志外发和监控；移动 100M 的 SQM/CAKE 需单独测试，联通 1G 默认不开。
8. OpenClash、Mihomo、订阅和 GEO 数据**没有预装**。先让基础双 WAN/PBR 稳定，再按
   [OpenClash 文档](openclash.md)独立安装，并明确 nftables、DNS、fwmark 和 ip rule 所有权。

## 8. 真机验收清单

| 检查项 | 通过标准 |
| --- | --- |
| 冷启动/重启 | 连续两次重启和一次断电冷启动均正常，UBI 无错误 |
| 管理面 | 有线 LuCI/SSH 可用；WAN 侧无法访问 LuCI/SSH |
| 身份与版本 | board/profile/version/分区变体全部匹配 |
| 无线 | 2.4G 和两路 5G 的 HE80 稳定；HE160 单独记录，不影响上线 |
| 联通 WAN | 1G 链路、DNS、NAT、IPv4/IPv6 和大文件下载正常 |
| 移动专线 | 100M 链路、指定上传策略和故障回退符合设计 |
| VLAN | management/office/server/iot/guest 隔离及必要访问逐项通过 |
| PBR | 每个策略按连接选择出口，回程一致，无同一连接拆分上下行 |
| 企业能力 | WireGuard、日志外发、监控、备份与恢复演练通过 |
| OTA | 只检查和下载；管理员确认前绝不自动刷写 |
| 救援 | 串口/U-Boot/恢复流程和离线文件实际可用 |

全部证据完成前，本版本保持 RC 状态，不进入企业生产稳定通道。

## 9. 启动失败或无法访问时

等待满 10 分钟后仍无法访问时：

1. 保持电源稳定，不要反复断电或连续按 Reset。
2. 只接一台有线电脑，依次检查 DHCP、`192.168.1.1` 和各 LAN 口。
3. 查看串口/U-Boot 输出，按已验证的暗云 Boot 救援流程操作。
4. 保留 MIBIB、APPSBL/U-Boot、校准分区和离线证据，不要覆盖 bootloader。
5. 不要为了“试一下”刷官方标准分区镜像、factory 镜像或其他 AX9000 固件。

刷机后若能启动但某项企业功能失败，先保留日志和配置，回到隔离测试网络处理；不要把尚未
验收的路由器接入公司生产交换网络。

## 最终结论

这份 RC3 镜像对**已采证的这一台暗云 Boot 大分区 AX9000**已经达到“受控现场首次刷写”
条件。它尚未达到“企业生产稳定版”条件；真正的稳定结论只能在你完成首次刷写并把本页真机
矩阵逐项跑通后给出。
