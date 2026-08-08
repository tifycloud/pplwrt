# 安全基线

- 管理面只在 LAN/管理 VLAN，WAN 禁止 LuCI/SSH；LuCI 使用 `luci-ssl-openssl`，首次登录立即更换随机密码。
- SSH 关闭密码登录或限制管理网段，保存 host key 指纹；不要把 root 密码、API token、WireGuard/OpenClash 私钥提交仓库。
- 使用 `firewall4` 默认拒绝 WAN 入站、SYN flood protection、NAT 和最小化 forwarding。所有自定义 nft 规则要有 owner、变更单和回滚。
- OTA 只允许校验过的 release manifest、profile 和 SHA256；`ota-apply.sh` 要求 root、镜像测试和 `--confirm VERSION`。
- 日志与配置备份可含地址、域名、订阅、密钥和用户数据，保存在加密离线介质；不要放入 `artifacts/` 或公开 release。
- 审查第三方 APK/IPK 的签名、来源、ABI 和依赖；OpenClash 核心/订阅解耦，默认不自动下载。

固件安全不能替代设备厂商救援、物理访问控制、密码管理和定期恢复演练。
