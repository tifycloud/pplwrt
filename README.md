# CompanyWrt（小米 AX9000 企业边界模板）

CompanyWrt 是面向小米 AX9000 的长期维护型 OpenWrt ImageBuilder 项目。当前基线固定为官方 OpenWrt **25.12.5 stable**、`qualcommax/ipq807x`、标准分区和官方 `xiaomi_ax9000` profile。项目以可重复的 ImageBuilder 构建为主；只有需要修改 DTS、分区或 BDF 时，才转入 Buildroot/源码构建。

> 这是可审计的固件工程模板，不是对任何型号、无线区域或运营商配置的保证。第一次刷写、切换分区和 OTA 必须由管理员在串口/救援路径可用的情况下执行，并先做配置与日志备份。

## 快速开始

```sh
git clone <your-companywrt-remote> pplwrt
cd pplwrt
./scripts/build-imagebuilder.sh --profile xiaomi_ax9000 --channel stable
(cd artifacts/stable && sha256sum -c SHA256SUMS)
```

构建脚本会核对官方 ImageBuilder tarball 的 SHA256、核对 `profiles.json` 中的实际 profile，然后以 `make image PROFILE=xiaomi_ax9000` 构建。脚本默认使用官方 feeds，不下载 OpenClash 核心或订阅，也不会把 `mwan3` 放入基础镜像。

输出位于 `artifacts/stable/`：固件、`manifest`、`VERSION`、`SHA256SUMS` 和构建元数据。`artifacts/` 中的二进制默认被 git 忽略；发布时由 CI 上传 release artifacts。

## 默认边界

- 双 WAN 使用 `firewall4`/nftables、`pbr` 和显式 fwmark/ip rule 策略；基础版不安装 `mwan3`。
- LuCI、`luci-ssl`、简体中文、官方救援主题和 CompanyWrt 的可运行管理页预装。
- OpenClash 仅预装官方依赖，插件本体、mihomo 核心和订阅分离；其规则链、fwmark 与 PBR 必须按文档选择唯一所有者。
- Wi-Fi 默认 HE80。HE160 只在兼容的监管域、客户端和 BDF 经过实测后单独启用；BDF workaround 独立于基础配置。
- VLAN、WireGuard、WAN、日志/配置备份、SQM、监控和机密信息均不写入 git；使用本地 overlay 或加密的管理员存储。
- 官方、USTC、TUNA feeds 可按顺序恢复切换，但发布构建必须锁定 URL、版本和校验。

详细操作按 [docs/README.md](docs/README.md) 导航。请先读 [docs/flash.md](docs/flash.md)、[docs/security.md](docs/security.md) 和 [docs/ota.md](docs/ota.md)。
