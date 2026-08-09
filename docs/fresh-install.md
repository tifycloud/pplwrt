# CompanyWrt 全新安装教程（AX9000 暗云 Boot 大分区）

> 当前适用版本：`25.12.5-company.2-rc5`
>
> 当前状态：已通过远端完整编译、签名、固件内容、不可变发布和供应链证明检查；**仍是 RC，不是企业稳定版**。
>
> 适用设备：本项目已经采证的 Xiaomi AX9000，暗云 Boot 单 UBI 大分区布局。其他 AX9000 不得照抄。

本教程用于把已核验的 KWRT 设备**全新安装**为 CompanyWrt。刷写使用 `-n`，不会保留
KWRT 配置。教程不修改 MIBIB、U-Boot 或无线校准分区，也不使用 factory 镜像。

独立网页排版版见 [fresh-install.html](fresh-install.html)。刷机前还应阅读
[分区兼容性说明](ax9000-partition-compatibility.md)和[刷机与救援说明](flash.md)。

## 0. 先判断你现在运行的是什么系统

- **已经运行 CompanyWrt RC2/RC3**：board 已经是 `xiaomi,ax9000-darkyun`，不要再用首次
  迁移的 `-F`。在 LuCI 的“系统 → 备份/升级”上传本页 RC5 sysupgrade 镜像即可。若要完整
  体验新的四步首次设置向导，请先备份配置，然后**取消“保留设置”**；这会清空现有配置。
- **仍运行 KWRT，board 是 `xiaomi,ax9000`**：属于一次性身份迁移，必须继续执行本教程的
  暗云硬件指纹门禁和 `sysupgrade -T -F` 只测试步骤。
- **任何其他系统、board 或分区**：停止，不使用本教程，也不使用 `-F`。

### 现有 CompanyWrt RC2/RC3：换一台 Windows 电脑升级 RC5

1. 在新 Windows 电脑上从第 3 节 Release 下载 RC5 sysupgrade，并用 PowerShell 校验 SHA256。
2. 路由器搬到电脑旁、正常通电启动；Windows 网卡保持“自动获取 IP/DNS”，用网线只连接
   路由器 LAN，暂时不要接两条 WAN。
3. 等待约 3 分钟，浏览器访问当前管理地址（全新默认是 `https://192.168.1.1/`）并登录。
4. 进入“系统 → 备份/升级”，先下载一份当前配置备份，再上传 RC5 的 sysupgrade 文件。
5. **不要勾选强制升级。**系统应识别为同一个 `xiaomi,ax9000-darkyun` 设备；若仍提示
   board/image 不兼容，停止并保存原始提示。
6. 为了验证新版 Liquid 和首次向导，本次建议关闭“保留设置”。这等同 `sysupgrade -n`，会
   清除当前宽带、Wi-Fi、密码和插件配置；确认备份已保存后再继续。若选择保留设置，向导
   可能不会再次出现。
7. 点击正式升级后不关浏览器、不拔电、不按 Reset，等待至少 8–10 分钟；随后重新获取网络
   地址并访问 `https://192.168.1.1/`。
8. 在“胖胖龙专用路由器”四步向导中设置管理员密码、主 WAN 和三射频 Wi-Fi。联通光猫桥接
   时选 PPPoE 并填写宽带账号/密码；光猫已拨号时选 DHCP。

这一条升级路径不修改 bootloader/MIBIB，也不使用 `-F`；下面第 1–5 节的一次性迁移命令只
供仍运行 KWRT 的设备使用。

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

历史采证样机曾通过专属只读门禁，但现场仍须按第 4 节重新运行。**以下镜像一律禁止使用**：

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

## 3. 下载唯一正确的 RC5 镜像

从 [CompanyWrt RC5 Release](https://github.com/tifycloud/pplwrt/releases/tag/v25.12.5-company.2-rc5)
下载：

```text
openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin
```

镜像的固定信息：

```text
大小：19118685 bytes
SHA256：a9d2425017d76367f76d709ce7a6fa8de53d1f664e0e1514c27f9dfc06dfc1ed
```

Windows PowerShell 校验：

```powershell
Get-FileHash .\openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin -Algorithm SHA256
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

## 4. 从 KWRT 首次迁移前，重新运行刷前门禁

RC5 的发布检查不能代替目标路由器的现场检查。只要路由器重启过、换过固件或更换过设备，
此前 `/tmp` 中的门禁结果就已经失效，必须在本次维护窗口重新完成：

- MIBIB、两份 APPSBL、MTD/UBI 和当前升级脚本指纹核对；
- RC5 manifest 的 usign 签名、下载大小和 SHA256 核对；
- profile、board、分区变体和来源版本绑定；
- `sysupgrade -T -F` **只测试不写入**；
- 专属内核 DTB 和单 UBI 升级路径的构建/内容检查。

从 RC5 Release 同时下载下列文件，经有线管理电脑上传到路由器新建的
`/tmp/companywrt-rc5/` 目录：

```text
ax9000-darkyun-preflight.sh
ax9000-darkyun-first-flash.sh
ota-common.sh
companywrt-release.pub
RELEASE-MANIFEST
RELEASE-MANIFEST.sig
openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin
```

RC5 Release 的 `ax9000-darkyun-first-flash.sh` 会依次核对 MIBIB、两份 APPSBL、MTD、UBI、
当前 KWRT 升级脚本、CompanyWrt usign 签名、镜像大小/SHA 和 board，然后仅运行
`sysupgrade -T -F`。它只打印最后的刷写命令，不会替你刷写。

> 当前已采证的 KWRT 没有内置 `usign`。缺少 `usign` 时必须停止，由维护者使用已审计的
> 临时工具流程重新执行门禁；不要从未知软件源安装，不要删掉签名检查，也不要只凭网页
> 下载成功就直接使用 `-F`。

确认 `usign` 来自已审计流程并可运行后，在路由器 SSH 中执行下面的**只读门禁**：

```sh
cd /tmp/companywrt-rc5
chmod 0700 ax9000-darkyun-preflight.sh ax9000-darkyun-first-flash.sh ota-common.sh
./ax9000-darkyun-first-flash.sh \
  --manifest ./RELEASE-MANIFEST \
  --signature ./RELEASE-MANIFEST.sig \
  --image ./openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin \
  --public-key ./companywrt-release.pub \
  --expected-version 25.12.5-company.2-rc5 \
  --confirm-version 25.12.5-company.2-rc5 \
  --confirm-sha256 a9d2425017d76367f76d709ce7a6fa8de53d1f664e0e1514c27f9dfc06dfc1ed
```

只有看到 `FIRST-FLASH CANDIDATE PASSED ALL AUTOMATED GATES` 才能继续。脚本不会刷机，只会
打印最终命令和随机工作目录。

门禁通过后，它会打印本次随机工作目录中的候选路径。正式刷写前，在路由器上再核对一次：

```sh
sha256sum '/tmp/companywrt-first-flash.XXXXXX/ota/openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin'
```

必须仍然得到：

```text
a9d2425017d76367f76d709ce7a6fa8de53d1f664e0e1514c27f9dfc06dfc1ed
```

> **如果路由器已经重启，立即停止。** `/tmp` 是内存盘，重启后门禁结果和镜像都会消失。
> 不要仅重新上传镜像后手工使用 `-F`。必须重新运行完整的签名 + 硬件指纹 + 强制测试门禁。
> 当前 KWRT 没有内置 `usign`，因此应由维护者按已审计流程重新准备门禁环境；不得从未知
> KWRT 软件源随意安装工具，也不得跳过签名验证。

## 5. 执行全新安装

只有在以下条件同时满足时才执行：有线直连、救援可用、电源稳定、路由器未在门禁后重启、
门禁打印的随机路径存在、SHA256 正确，并且现场管理员明确同意刷写。下面的 `XXXXXX` 必须
替换成门禁实际打印的目录名，不能原样复制。

```sh
sysupgrade -n -F '/tmp/companywrt-first-flash.XXXXXX/ota/openwrt-qualcommax-ipq807x-xiaomi_ax9000_darkyun-squashfs-sysupgrade.bin'
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
  --expected-version 25.12.5-company.2-rc5
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
25.12.5-company.2-rc5
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
```

任何 `FAIL`、board/profile/version 不一致或 UBI 异常都应停止接入生产网络，保留日志并进入
救援检查；不要继续配置双 WAN。

## 7. 推荐的首次配置顺序

1. 设置时区、NTP、管理密码和 HTTPS，导出第一次干净配置备份。
2. 使用“胖胖龙专用路由器”四步向导设置主 WAN：联通宽带是 PPPoE 时填写运营商提供的
   宽带账号和密码；光猫已拨号时选择 DHCP。向导同时设置管理密码和三射频 Wi-Fi。
3. Wi-Fi 先使用 **HE80**；HE160 是 AX9000 专项测试项，不能作为首启默认值。
4. 先只连接联通宽带，确认 IPv4/IPv6、DNS、NAT 和 WAN 入站拒绝。
5. 再加入移动专线；联通作为办公/下载默认出口，移动用于服务器和指定稳定上传连接。
6. 逐个建立 management、office、server、iot、guest VLAN，并逐项验证隔离。
7. `company-network plan` 只生成待审阅计划，不会自动应用；确认端口、mark、table、DNS 和
   回滚方案后再人工落地。
8. WireGuard 已预装；日志外发、`collectd` 监控和 SQM 都按需安装/配置。移动 100M 的
   SQM/CAKE 需单独测试，联通 1G 默认不开。
9. OpenClash、Mihomo、订阅和 GEO 数据**没有预装**。先让基础双 WAN/PBR 稳定，再按
   [OpenClash 文档](openclash.md)独立安装，并明确 nftables、DNS、fwmark 和 ip rule 所有权。

## 8. 真机验收清单

| 检查项 | 通过标准 |
| --- | --- |
| 冷启动/重启 | 连续两次重启和一次断电冷启动均正常，UBI 无错误 |
| 管理面 | 有线 LuCI/SSH 可用；WAN 侧无法访问 LuCI/SSH |
| 身份与版本 | board/profile/version/分区变体全部匹配 |
| 空载内存 | 冷启动 10 分钟、无客户端/插件后执行 `/usr/share/company/memory-report --check-idle` 必须 PASS，`MemAvailable` 不低于 70% |
| 24 小时内存 | 同一空载条件下可用内存下降不超过 5 个百分点，无持续增长的异常进程 |
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

这份 RC5 镜像已经达到**已采证暗云 Boot 大分区 AX9000 的受控现场测试候选**条件。它尚未
达到“企业生产稳定版”条件；真正的稳定结论只能在你完成首次刷写或升级，并把本页真机矩阵、
空载内存和 24 小时稳定性逐项跑通后给出。
