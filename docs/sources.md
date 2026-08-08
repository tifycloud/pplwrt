# 一手来源与固定证据

以下 URL 是构建/审计使用的一手来源，访问时间为 2026-08-08（服务器目录显示 25.12.5，发布日期 2026-07-01）：

- [OpenWrt 25.12.5 release notes](https://openwrt.org/releases/25.12/notes-25.12.5)
- [qualcommax/ipq807x 25.12.5 目录（ImageBuilder、sha256sums、profiles.json、AX9000 镜像）](https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/)
- [官方 profiles.json](https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/profiles.json)
- [官方 sha256sums](https://downloads.openwrt.org/releases/25.12.5/targets/qualcommax/ipq807x/sha256sums)
- [OpenWrt ImageBuilder 使用说明](https://openwrt.org/docs/guide-user/additional-software/imagebuilder)
- [OpenWrt AX9000 设备页](https://openwrt.org/toh/xiaomi/ax9000)
- [OpenWrt generic sysupgrade](https://openwrt.org/docs/guide-user/installation/generic.sysupgrade)
- [OpenWrt usign source](https://git.openwrt.org/project/usign.git)
- [GitHub artifact attestation 官方文档](https://docs.github.com/en/actions/security-for-github-actions/using-artifact-attestations)
- [GitHub immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases)
- [GitHub deployment environments REST API](https://docs.github.com/en/rest/deployments/environments)
- [GitHub repository rulesets REST API](https://docs.github.com/en/rest/repos/rules)
- [OpenClash README（依赖列表）](https://github.com/vernesong/OpenClash/blob/master/README.md)
- [OpenClash Makefile（当前包依赖）](https://raw.githubusercontent.com/vernesong/OpenClash/master/luci-app-openclash/Makefile)
- [OpenClash 用户指南](https://github.com/vernesong/OpenClash/blob/dev/.github/skills/openclash-user-guide/SKILL.md)

25.12.5 `profiles.json` 的 `xiaomi_ax9000` 条目给出 `supported_devices: ["xiaomi,ax9000"]`、设备包 `ipq-wifi-xiaomi_ax9000 kmod-ath11k-pci ath11k-firmware-qcn9074 kmod-ath10k-ct ath10k-firmware-qca9887-ct`，以及本文 `devices/ax9000/profile.json` 中的四个官方镜像 SHA256。该条目而非文件名猜测是接受 profile 的依据。

逐包 inventory 以构建生成的 PACKAGE-MANIFEST 和 CycloneDX 一一映射为准；许可证仍需
结合 APK metadata、上游 source archive 与 LICENSE 文件。SBOM 的 `NOASSERTION` 是诚实的
未知状态，不是许可证缺失或已获许可的结论。关键 upstream copyright/license 入口汇总在
仓库根 `NOTICE`。CompanyWrt overlay 自有内容为 MIT，不能把 upstream package 许可证
概括成单一 MIT。
