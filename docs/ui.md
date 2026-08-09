# Liquid UI、胖胖龙品牌与首次设置

RC6 使用成熟的 `luci-theme-liquid` 作为完整 LuCI 默认主题，而不是继续自造一套容易漏掉
插件和系统页面的皮肤。源码固定到上游 commit
`ad0cce67c02ce9ce0154c2f08491fc8ac1daf06b`，由 OpenWrt Buildroot 编译为真实 APK。
全局导航、状态、接口、无线、防火墙、表单、表格、模态框、登录页和移动端都沿用 Liquid
完整实现；`luci-theme-openwrt-2020` 仍安装并注册，可在 Liquid 损坏时作为救援入口。
新安装默认使用深青灰配色；顶栏仍可切换亮色、深色或跟随系统，不锁死个人偏好。

CompanyWrt 的改造保持克制：顶部、登录标题、页面标题和页脚统一显示
**胖胖龙专用路由器**；控制中心和向导采用低饱和青绿色、明暗模式、响应式布局和可见键盘
焦点。网络 hostname 仍是合法 ASCII `companywrt-ax9000`，中文产品名只作为 UI/设备描述，
避免破坏 DHCP/DNS 兼容性。

上游可选 Bing 每日壁纸会在登录页渲染期间访问外部服务；CompanyWrt 已删除相关下载、缓存
和 shell 调用。主题偏好只通过已认证的 LuCI UCI RPC 写入 `/etc/config/liquid`，输入在服务
端模板再次限定为允许的模式、主题色和六位十六进制颜色。软件升级不会覆盖已有偏好。

首次登录自动进入三步设置向导，PPPoE/DHCP 直接显示在第一屏：

1. 选择主 WAN DHCP 或 PPPoE，填写联通宽带账号和密码；
2. 为三组 AX9000 AP 设置同一 SSID 与 WPA2/WPA3 密码，HE160 不在向导中开放；
3. 设置独立 root 管理员密码并保存。

有线管理和现场救援条件保留为非阻断提示，不再要求勾选一个无法自动识别的复选框。针对
RC5 真机出现的 `[object HTMLLabelElement]`，测试会执行实际 setup view 并复刻 LuCI
`dom.append()` 的非递归数组规则，防止 DOM 节点再次被当作字符串渲染。

宽带、Wi-Fi 与 root 密码只写入设备本地 UCI/passwd，不进入 company 配置、日志、镜像、
Git 或 release。移动专线、VLAN、PBR、WireGuard 和 OpenClash 不塞进首启向导，避免一次
提交过多高风险变更。

日常首页直接显示主 WAN、**可用内存、实际占用、总量、1 分钟负载和终端数**，再提供宽带、
Wi-Fi、双 WAN/PBR、备份入口。内存使用 `system.info.memory.available`（内核
`MemAvailable`），不再用 `MemTotal - MemFree` 把可回收 page cache 误报为应用占用。
LuCI 原生内存和存储进度条也直接显示字节数与百分比，不再要求鼠标悬停。详细风险门禁留在
文档和运维页面，不挡住基本设置路径。

UI 不静态声称 PBR、WAN、防火墙或无线已通过真机验收；运行状态仍需 ubus/nft/连接测试。
页面不得显示已有密码、订阅、私钥或完整日志正文。
