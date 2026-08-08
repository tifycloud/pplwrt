# AX9000 设备基线

`profile.json` 是从官方 25.12.5 `profiles.json` 逐字段核对后保存的证据，不是手写猜测。profile 必须传 `xiaomi_ax9000`，设备字符串必须是 `xiaomi,ax9000`；ImageBuilder 文件名和 SHA256 也固定在该文件中。

官方目录：<https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/>

标准分区只使用官方 factory/initramfs/sysupgrade 产物。不要在没有厂商救援/串口验证的情况下调整 rootfs 分区，也不要把 AX3600 的镜像用于 AX9000。HE80 是默认值，HE160 和任何 BDF 补丁都必须经过 `docs/test-matrix.md` 的射频测试并在独立分支/overlay 管理。
