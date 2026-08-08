# Roadmap

## 已完成（25.12.5-company.1）

- 官方 ImageBuilder/profile/镜像校验元数据固定。
- apk 基线、LuCI+luci-ssl+中文、官方救援主题、PBR/nftables 基础包。
- CompanyWrt UI MVP、双 WAN 配置生成器、管理员确认 OTA 包装器。
- CI 的稳定构建、manifest、SHA256 和 release artifact 流程骨架。

## 下一阶段

- 在真实 AX9000 上完成 factory/initramfs/sysupgrade 救援演练、双 WAN 故障注入和 HE160/BDF 矩阵。
- 将 CompanyWrt 两个 LuCI 包接入内部 APK/IPK feed，保留 overlay 构建作为故障回退。
- 加入签名 manifest（离线密钥在组织密钥库，永不入仓库）和回滚版本策略。
- 监控/日志集中化、SQM 参数模板和 VLAN/WireGuard 设备实测。

## Buildroot 入口条件

只有 DTS、分区、内核、BDF 或启动链需要修改时才创建 Buildroot 分支；先记录上游 commit、工具链、分区表、救援手册和可回滚镜像，再让 CI 同时产出官方和定制路径。
