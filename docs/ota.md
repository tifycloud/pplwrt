# 签名 OTA、二次绑定与人工刷写

CompanyWrt 不提供无人值守 OTA。每个候选 release 必须同时包含镜像、严格
`RELEASE-MANIFEST`、`RELEASE-MANIFEST.sig`、`SHA256SUMS`、包清单、SBOM、NOTICE、
MIT LICENSE、内容报告和 GitHub artifact attestation。

## 严格 manifest（15 字段）

格式为每行一个 `KEY=value`，不允许空行、注释、未知字段或重复字段：

```text
FORMAT=companywrt-release-v1
VERSION=25.12.5-company.2-rc1
OPENWRT_RELEASE=25.12.5
PROFILE=xiaomi_ax9000
BOARD=xiaomi,ax9000
CHANNEL=rc
TAG=v25.12.5-company.2-rc1
SOURCE_COMMIT=<40-lowercase-hex>
IMAGE=<safe-sysupgrade-basename>
SHA256=<64-lowercase-hex>
SIZE=<positive-byte-count>
URL=https://.../<IMAGE>
SIGNATURE=RELEASE-MANIFEST.sig
SIGNATURE_URL=https://.../RELEASE-MANIFEST.sig
USIGN_KEY_ID=679439846de7ada5
```

远程 manifest、signature 和 image 都只允许 HTTPS，curl redirect 也限制为 HTTPS。
签名使用固件内 `/etc/companywrt/keys/release.pub` 的 usign key；manifest 签名把
version/profile/board/channel/tag/commit/image/size/SHA/URL 绑定为一个整体。

## 下载检查（不改变路由器状态）

```sh
/usr/share/company/ota-check \
  --manifest https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2-rc1/RELEASE-MANIFEST \
  --version 25.12.5-company.2-rc1 --channel rc
```

它必须实际下载 signature 和完整 image，然后按顺序验证 schema、key fingerprint、
usign signature、实际字节数和 SHA256。短 SHA、仅打印 manifest SHA、HTTP 或假签名
均不能通过。manifest/signature 各有 64 KiB 下载上限，镜像下载上限由签名 SIZE 绑定
且全局不超过 512 MiB，避免未验证输入耗尽空间。离线介质可显式传
`--signature FILE --image FILE`，验证强度不降低。

## 目标设备准备（仍不刷写）

```sh
/usr/share/company/ota-apply \
  --manifest /tmp/bundle/RELEASE-MANIFEST \
  --signature /tmp/bundle/RELEASE-MANIFEST.sig \
  --image /tmp/bundle/<sysupgrade.bin> \
  --expected-version 25.12.5-company.2-rc1 \
  --expected-channel rc \
  --confirm-version 25.12.5-company.2-rc1 \
  --confirm-sha256 <64HEX_FROM_SEPARATE_ADMIN_REVIEW>
```

`ota-apply` 不信任先前的 ota-check 结果，会复制/下载后重新验证全部绑定，并通过
`ubus`+`jsonfilter` 核对真实 `xiaomi,ax9000`、`qualcommax/ipq807x`、OpenWrt release，
再核对安装的 build.conf profile/channel/version。它拒绝未审阅的同版本重装，要求
版本和 SHA 两次独立确认，只执行 `sysupgrade -T`。通过后仅打印最终人工
`sysupgrade '<verified-file>'`，不会执行、重启或自动重试。

管理员仍须先完成配置/日志备份、boot slot/MTD/secure boot/救援和断电证据。
GitHub attestation 是额外 provenance，不替代 usign、大小/SHA、board 或真机门禁。

## 密钥和 CI

公钥可提交；私钥只存在受控密钥库和 GitHub encrypted secret
`COMPANYWRT_USIGN_SECRET_KEY`。tag/stable 构建缺 secret 或 fingerprint 不符即失败。
轮换公钥必须先发布包含新公钥和迁移说明的过渡固件，不能直接覆盖信任锚。
