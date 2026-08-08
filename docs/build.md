# 构建与证据

官方目录：<https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/>。

固定 ImageBuilder：

```text
openwrt-imagebuilder-25.12.5-qualcommax-ipq807x.Linux-x86_64.tar.zst
SHA256 81faa256975900d1d5f07d57c06881996802ef09f3d7ee27e74cb99136e7a6b5
```

profile 从官方 `profiles.json` 核对为 `xiaomi_ax9000`，支持设备 `xiaomi,ax9000`。不要从文件名猜 profile；`scripts/build-imagebuilder.sh` 会再次验证 metadata。

## 本地 Linux/容器

```sh
./scripts/build-imagebuilder.sh --profile xiaomi_ax9000 --channel stable
(cd artifacts/stable && sha256sum -c SHA256SUMS)
```

官方 tarball 内 host helper 是 Linux x86_64。Apple Silicon 使用：

```sh
./scripts/build-in-container.sh --profile xiaomi_ax9000 --channel stable
```

容器脚本要求已启动的 Docker/OrbStack/Colima daemon，并固定 `ubuntu:24.04`、`linux/amd64`；不在宿主机安装大型虚拟化软件。GitHub Actions 同样使用 Linux x86_64 runner。

构建将官方 profile 包、LuCI/PBR/OpenClash 依赖和 overlay 合并，生成 sysupgrade 镜像、完整包 manifest、`RELEASE-MANIFEST`、`VERSION` 和 `SHA256SUMS`。OpenClash 本体、mihomo 核心和订阅不进入镜像。

## 复核要求

- `make manifest PROFILE=xiaomi_ax9000` 中没有 `mwan3`。
- manifest 中包含 `firewall4`、`nftables`、`pbr`、`luci-ssl-openssl` 和中文包。
- 目标镜像文件名含 `xiaomi_ax9000`，校验值与构建输出一致。
- CI 只发布稳定版本或显式 beta，不能把未验证 HE160/BDF overlay 混入 stable。
