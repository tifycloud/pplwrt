# 官方、USTC、TUNA 源与恢复

默认 feeds 固定为官方 25.12.5 目录；ImageBuilder 的 `repositories` 文件记录了 target、base、luci、routing 等 APK 索引。USTC 和 TUNA 只作为网络不可达时的恢复路径：

```text
official https://downloads.openwrt.org/releases/25.12.5
USTC     https://mirrors.ustc.edu.cn/openwrt/releases/25.12.5
TUNA     https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases/25.12.5
```

切换前后必须比较相同 target/profile 路径、APK index、包版本、签名和 SHA256；恢复官方源后再进行 release 构建。不要在生产设备上混用不同 release/架构的索引，也不要为了“能安装”关闭签名检查。`scripts/feeds-fallback.sh` 只打印计划，不自动修改源。
