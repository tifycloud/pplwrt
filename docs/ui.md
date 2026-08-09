# CompanyWrt UI 与首次设置

RC4 把 `luci-theme-company-overlay` 升级为完整 LuCI 主题，而不是只给单个 dashboard 加
CSS。全局导航、状态、接口、无线、防火墙、表单、表格、模态框和移动端使用同一套视觉
语言；`luci-theme-openwrt-2020` 仍安装并注册，可在公司主题损坏时作为救援入口。

首次登录自动进入四步设置向导：

1. 确认有线 LAN、隔离网络和现场救援条件；
2. 选择主 WAN DHCP 或 PPPoE，填写联通宽带账号和密码；
3. 为三组 AX9000 AP 设置同一 SSID 与 WPA2/WPA3 密码，HE160 不在向导中开放；
4. 设置独立 root 管理员密码并保存。

宽带、Wi-Fi 与 root 密码只写入设备本地 UCI/passwd，不进入 company 配置、日志、镜像、
Git 或 release。移动专线、VLAN、PBR、WireGuard 和 OpenClash 不塞进首启向导，避免一次
提交过多高风险变更。

日常首页优先回答四个问题：互联网是否在线、还剩多少**可用**内存、有多少终端、最常用
操作在哪里。内存使用 `system.info.memory.available`（内核 `MemAvailable`），不再用
`MemTotal - MemFree` 把可回收 page cache 误报为应用占用。详细风险门禁留在文档和运维
页面，不挡住宽带/Wi-Fi/备份的基本路径。

UI 不静态声称 PBR、WAN、防火墙或无线已通过真机验收；运行状态仍需 ubus/nft/连接测试。
页面不得显示已有密码、订阅、私钥或完整日志正文。
