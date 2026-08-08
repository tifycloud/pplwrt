# 签名 OTA、二次绑定与人工刷写

CompanyWrt 不提供无人值守 OTA。每个候选 release 必须同时包含镜像、严格
`RELEASE-MANIFEST`、`RELEASE-MANIFEST.sig`、`SHA256SUMS`、包清单、SBOM、NOTICE、
MIT LICENSE、内容报告和 GitHub artifact attestation。

## 严格 manifest（暗云 RC/beta v1 为 19 字段，stable v2 为 24 字段）

格式为每行一个 `KEY=value`，不允许空行、注释、未知字段或重复字段：

```text
FORMAT=companywrt-darkyun-release-v1
VERSION=25.12.5-company.2-rc3
OPENWRT_RELEASE=25.12.5
PROFILE=xiaomi_ax9000_darkyun
BOARD=xiaomi,ax9000-darkyun
PARTITION_VARIANT=darkyun-large-ubi-v1
MIBIB_SHA256=2d79c1b15b8946af733dba5fff5e33bf3ba18863ed734710bd2a5e48fc469c11
APPSBL_SHA256=80908e502add45ee6aa7ad83aa16ec2c3c8bf27b572ac0f9c3fe404b94fc0007
MIGRATION_BOARD=xiaomi,ax9000
CHANNEL=rc
TAG=v25.12.5-company.2-rc3
SOURCE_COMMIT=<40-lowercase-hex>
IMAGE=<safe-sysupgrade-basename>
SHA256=<64-lowercase-hex>
SIZE=<positive-byte-count>
URL=https://.../<IMAGE>
SIGNATURE=RELEASE-MANIFEST.sig
SIGNATURE_URL=https://.../RELEASE-MANIFEST.sig
USIGN_KEY_ID=<16HEX_PRIMARY_SIGNING_KEY_ID>
```

stable 不能使用 v1。v2 还必须包含：

```text
HARDWARE_VALIDATION=VERIFIED
PRODUCTION_GATE_SHA256=<64HEX_EXACT_EVIDENCE_FILE_SHA>
HARDWARE_EVIDENCE_ID=<OPAQUE_CONTROLLED_SYSTEM_ID>
SERIAL_EVIDENCE_ID=<OPAQUE_REDACTED_RECORD_ID_NOT_RAW_SERIAL>
TESTED_FIRMWARE_SHA256=<MUST_EQUAL_SHA256>
```

RC/beta 不允许伪造这些 stable 字段，其 BUILD-METADATA 与内容报告明确写
`NOT_PERFORMED_RC_ONLY`。

远程 manifest、signature 和 image 都只允许 HTTPS，curl redirect 也限制为 HTTPS。
签名使用固件内 `/etc/companywrt/keys/release.pub` 的 usign key；manifest 签名把
version/profile/board/partition/MIBIB/APPSBL/channel/tag/commit/image/size/SHA/URL 绑定为一个整体。
RC2 是已完成的轮换例外：`RELEASE-MANIFEST.sig` 仍由 RC1 旧 key 主签，
`RELEASE-MANIFEST.next.sig` 由新 key 对同一字节共签，RC2 rootfs 只嵌入新 key。这样
RC1 无需信任锚 override 即可验证过渡；当前 RC3 由新 key 对
`RELEASE-MANIFEST.sig` 主签，不再生成 `.next.sig`。

## 下载检查（不改变路由器状态）

```sh
/usr/share/company/ota-check \
  --manifest https://github.com/tifycloud/pplwrt/releases/download/v25.12.5-company.2-rc3/RELEASE-MANIFEST \
  --version 25.12.5-company.2-rc3 --channel rc
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
  --expected-version 25.12.5-company.2-rc3 \
  --expected-channel rc \
  --confirm-version 25.12.5-company.2-rc3 \
  --confirm-sha256 <64HEX_FROM_SEPARATE_ADMIN_REVIEW>
```

`ota-apply` 不信任先前的 ota-check 结果，会复制/下载后重新验证全部绑定，并通过
`ubus`+`jsonfilter` 核对真实 `xiaomi,ax9000-darkyun`、`qualcommax/ipq807x`、OpenWrt
release，再核对安装的 build.conf profile/board/partition/channel/version。它拒绝未审阅的同版本重装，要求
版本和 SHA 两次独立确认，只执行 `sysupgrade -T`。通过后仅打印最终人工
`sysupgrade '<verified-file>'`，不会执行、重启或自动重试。

> **不可覆盖的生产规则：** `ota-apply` 固定使用
> `/etc/companywrt/keys/release.pub`，生产 CLI 禁止 `--public-key`。该参数只在自动化测试
> 同时提供 `--test-mode`、`COMPANYWRT_OTA_TEST_MODE=1` 和位于进程临时目录下的
> `COMPANYWRT_DEVICE_ROOT` 时开放。不要把 test mode 当作设备运维入口。

standalone `ota-check` 不会调用 `sysupgrade` 或读设备状态，因此仍允许 `--public-key`
用于离线介质、CI 和历史 RC1 资产审计；这不改变设备端 apply 的固定信任锚。

管理员仍须先完成配置/日志备份、boot slot/MTD/secure boot/救援和断电证据。
GitHub attestation 是额外 provenance，不替代 usign、大小/SHA、board 或真机门禁。

## 密钥和 CI

公钥可提交；新私钥只存在受控密钥库和 GitHub `firmware-signing` environment secret
`COMPANYWRT_USIGN_CURRENT_SECRET_KEY`。旧 repository secret 只曾用于生成兼容 RC1 的
RC2 过渡主签；RC2 双签、资产 digest、attestation 和 OTA E2E 核验后已经删除。
tag/stable 构建缺 secret 或 fingerprint 不符即失败。环境还要求审批、wait timer 和
仅 `main` branch/`v*` tag deployment policy；tag ruleset 禁止删除/移动已创建的 release tag。
