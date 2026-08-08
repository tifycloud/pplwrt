# AX9000 设备基线

`profile.json` 保存官方 25.12.5 标准布局 profile/SHA，仅作为上游对照证据，不能用于
这台暗云 Boot 路由器。实际构建规格是 `darkyun-large-ubi.json`，profile 为
`xiaomi_ax9000_darkyun`，运行 board 为 `xiaomi,ax9000-darkyun`；一次迁移时允许识别旧
`xiaomi,ax9000` 只用于只读指纹门禁，不会把它加入镜像的广泛兼容列表。

官方目录：<https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/>

`patches/0001-*` 基于官方 tag 的精确 commit，新增单一 232 MiB rootfs UBI、cfg_bak、专属
升级脚本和板级映射；不生成 factory 产物，也不写 MIBIB/APPSBL/ART。不要把官方标准
AX9000、AX3600 或历史 CompanyWrt 标准布局镜像用于该目标。HE80 是默认值，HE160 和
任何 BDF 补丁都必须经过 `docs/test-matrix.md` 的射频测试并独立管理。
