# Changelog

## 25.12.5-company.2-rc6 — 2026-08-09

**Release candidate / NOT PRODUCTION.** RC5 真机首次设置反馈暴露了一个阻断型 LuCI DOM
渲染错误和两个直接体验问题，RC6 专门修复，不把 RC5 宣称为可继续验收的候选。

- 根因是 `setup.js` 把 `content` 元素数组作为 `dom.content()` 顶层数组的一个成员；LuCI
  官方 `dom.append()` 不递归展开嵌套数组，而是把它转为字符串，真机因此显示
  `[object HTMLLabelElement],[object HTMLParagraphElement]`。新增执行真实 view 源码并复刻
  LuCI DOM 追加规则的 Node 回归测试，修复前稳定失败、修复后通过。
- 删除阻断流程的“确认有线”复选框，把 PPPoE/DHCP 直接放到第一屏；向导收敛为宽带、
  Wi-Fi、管理密码三步，安全提醒只提示、不再拦截。控制中心继续提供可重复进入的宽带入口。
- 所有 LuCI 原生 memory/storage progressbar 把 `title` 中的字节数与百分比直接印在条形图
  上，触摸屏和键盘不再依赖 hover。
- 控制中心改为更紧凑的操作台布局，直接展示 WAN、`MemAvailable`、实际占用、总量、
  1 分钟负载和终端数，并解释 OpenWrt 传统“已用”会把文件缓存计入。
- Liquid APK 升为 `0.3.1-r2` 以强制 CSS/JS 缓存版本变化；包集合仍固定 214 个，
  OpenClash、Mihomo、collectd、Ruby、TUN/TProxy 和 SQM 继续不预装。
- 68% 的真机反馈来自原生状态页传统 `Used = total - free` 口径，不能单独证明内存泄漏；
  生产判断仍要求冷启动 10 分钟后的 `memory-report --check-idle` 原始输出和 24 小时复测。

## 25.12.5-company.2-rc5 — 2026-08-09

**Release candidate / NOT PRODUCTION.** RC4 在签名和发布前取消；没有 RC4 Release 或可刷
资产。RC5 按用户确认的设计方向换用成熟 Liquid 主题，并保留 RC4 已完成的首次设置和
空载内存优化。

- 固定并 vendor `zzsj0928/luci-theme-liquid` commit
  `ad0cce67c02ce9ce0154c2f08491fc8ac1daf06b`，由完整 OpenWrt Buildroot 编译为真实
  `luci-theme-liquid` APK；官方 OpenWrt2020 继续作为救援主题。
- 登录页、顶栏、页面标题、页脚、控制中心和向导统一显示“胖胖龙专用路由器”；网络
  hostname 保持兼容 DHCP/DNS 的 `companywrt-ax9000`。
- 删除上游 Bing 外部壁纸下载、缓存与模板 shell 执行路径；删除直接写文件的主题
  controller。主题偏好改为已认证 LuCI UCI RPC，并在服务端限定 mode/accent/颜色值。
- 保留四步主 WAN DHCP/PPPoE、Wi-Fi 和 root 密码向导；CompanyWrt 控制中心视觉与 Liquid
  明暗模式、移动端和焦点状态统一。
- Liquid 上游仓库 LICENSE 与源码头/Makefile 的许可证声明不一致；保留完整上游告知并
  暂按更严格的 GPL-3.0-only 声明，安装许可证正文并在 SBOM 单列 CompanyWrt patch。
- 预期基础 manifest 为 214 个包，仅比 RC4 增加真正的 Liquid APK；OpenClash、Mihomo、
  collectd、Ruby、TUN/TProxy 和 SQM 仍不进入基础镜像。

## 25.12.5-company.2-rc4 — 2026-08-09

**CANCELED BEFORE SIGNING / NO RELEASE / DO NOT FLASH.** 本轮针对首次刷写后的直接用户
反馈重做产品体验与空载基线；在发布工作流进入签名阶段前因 UI 方向调整而取消。其内存
瘦身和首装向导由 RC5 继承，但 RC4 tag 不对应任何 Release 资产。

- `luci-theme-company` 从单页 CSS 升级为完整 LuCI 主题，统一导航、表单、表格、状态、
  移动端和键盘焦点；OpenWrt2020 仍作为救援主题保留。
- 新增首次设置向导：有线确认、主 WAN DHCP/PPPoE、宽带账号/密码、三射频 Wi-Fi、
  WPA2/WPA3 密码与 root 管理密码。敏感字段只提交到设备 UCI/passwd，不进入镜像或 Git。
- 日常首页改为联网、终端、真实可用内存和四个常用任务；高级门禁信息移回运维文档。
- 内存口径改用内核 `MemAvailable`，新增只读 `memory-report`，列出可回收缓存与最大 RSS
  进程，避免把 page cache 误报为应用常驻占用。
- 从基础镜像删除 collectd 及其插件、Ruby/Ruby-YAML、Lua compatibility runtime、bash、
  unzip、TUN/tproxy 等 39 个 package selections；OpenClash 安装时再解析完整依赖。
- 基础 manifest 从 252 个包收敛为固定 213 个包；collectd 不再依靠首启脚本删除
  `S80collectd`，而是完全不进入 rootfs。

## 25.12.5-company.2-rc3 — 2026-08-09

**Release candidate / NOT PRODUCTION.** 基础固件继续不预装 OpenClash、Mihomo、订阅或
敏感配置；仅保留可复用依赖。公司控制台明确显示“本体未安装”，移除指向不存在页面的
OpenClash 链接。RC3 使用 RC2 已嵌入的当前 usign key 主签，不再读取旧 RC1 私钥。

## 25.12.5-company.2-rc2 — 2026-08-08

**Release candidate / NOT PRODUCTION.** 仍无 AX9000 真机 production-gate 证据；本轮只加固
静态、构建、签名与发布门禁，不创建 stable tag。RC2 已作为不可变 prerelease 发布并完成
旧/新 key 双签验证；构建目标为实机指纹绑定的暗云 Boot 单 UBI 专属变体。

- 真机只读确认 MIBIB 为 `rootfs=0x01180000+0x0e800000`，两个 APPSBL 指纹一致，运行时
  为单 UBI `kernel/rootfs/rootfs_data`；历史标准布局 RC 明确禁止刷入。
- 从官方 ImageBuilder 切换为固定 OpenWrt 25.12.5/feeds commit 的完整 Buildroot；新增
  `xiaomi_ax9000_darkyun` DTS/profile/board/upgrade patch，不生成 factory 镜像。
- 新增 MIBIB/APPSBL/MTD offset/UBI 只读迁移 preflight，并固定当前 KWRT
  `sysupgrade/platform/nand` 三份脚本指纹；release manifest、OTA、production gate 绑定
  专属 board、partition variant 和 bootloader 指纹。
- inspector 从 sysupgrade FIT 提取 DTB，拒绝 `ubi_kernel`，要求 232 MiB rootfs、cfg_bak、
  `/dev/ubiblock0_1` 与专属 compatible 全部吻合。

- 发布必须使用 annotated `v$VERSION` tag，且 peeled commit 与实时拉取的受保护
  `origin/main` HEAD 精确相等；签名 job 绑定 `firmware-signing` environment（审批、冷却、
  仅 `main` branch/`v*` tag policy）。active tag ruleset 禁止 `v*` 删除/非 fast-forward，
  仍允许合法新 RC tag。
- 完整 OpenWrt Buildroot/inspector 在无 secret job 中完成；unsigned bundle 先封存
  SHA256SUMS。隔离签名 job 重新核验 protected main、source commit、内容报告和真机状态，
  只生成 manifest/签名，不调用编译器、make 或下载步骤。
- 开启 GitHub 原生 immutable releases；先上传完整 draft 再发布，发布后逐资产比对 digest，
  并验证 GitHub release attestation 和每个本地资产。
- 完成 RC1→RC2 显式 usign 轮换：旧 key 主签保证 RC1 可升级，新 key 共签并嵌入 RC2；
  新私钥只存 environment secret，RC2 核验后删除旧 repository secret。
- 固件 inspector 实际读取解包 rootfs `/etc/shadow`；只接受 root 密码字段 EMPTY 或 LOCKED，
  拒绝任意预置 hash，报告具体状态且不输出 hash。
- RC 证据状态固定为 `NOT_PERFORMED_RC_ONLY`。stable 构建必须读取且验证精确 gate 文件，
  把 `VERIFIED`、gate SHA、opaque hardware/serial evidence IDs 和被测固件 SHA 写入
  BUILD-METADATA、内容报告与严格 v2 release manifest，并要求构建 SHA 精确相等。
- CycloneDX 以暗云大分区目标构建出的 252 个唯一 PACKAGE-MANIFEST 包为基准建立一一上游组件映射；
  补齐 `libnghttp2-14` 缺项。无法从上游 SBOM 证明的许可证写 `NOASSERTION`，不宣称
  完整许可证结论。
- network plan 对 domain 大小写、IPv4 `/32`、CIDR host bits、单端口范围做规范化，拒绝
  mobile/unicom 间相同或重叠 destination/port policy。
- 设备端 `ota-apply` 的生产 trust anchor 固定为 `/etc/companywrt/keys/release.pub`；
  `--public-key` 只在显式、双重环境保护的临时 test mode 可用。standalone `ota-check`
  仍允许离线 CI 指定公钥。
- ShellCheck 扩展到 `tests/**/*.sh` 并清零告警；新增 shadow inspector、SBOM 一一覆盖、
  v2 hardware manifest、OTA key override 和网络规范化冲突测试。

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
