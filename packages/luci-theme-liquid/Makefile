include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-liquid
PKG_VERSION:=0.3.1
PKG_RELEASE:=3

PKG_MAINTAINER:=然后七年 <z@7ze.top>
PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE

LUCI_TITLE:=Liquid glass theme for 胖胖龙专用路由器 (LuCI >= 23)
LUCI_PKGARCH:=all
LUCI_DEPENDS:=+luci-base +rpcd-mod-ucode

# CompanyWrt vendors upstream commit ad0cce67c02ce9ce0154c2f08491fc8ac1daf06b.
# The repository-level LICENSE is GPL-3.0 although upstream source headers and
# metadata say Apache-2.0. We deliberately publish the vendored package under
# the stricter GPL-3.0-only declaration until upstream resolves the mismatch.

# 汉化/子包版本与主包保持同步
PKG_PO_VERSION:=$(PKG_VERSION)-r$(PKG_RELEASE)

# csstidy 会破坏 @media 块（只保留首条规则，其余泄漏到块外无条件生效），
# 导致移动端断点样式全部失效；本主题关闭 CSS 压缩，样式原样打包。
CONFIG_LUCI_CSSTIDY:=

define Package/$(PKG_NAME)/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	uci -q delete luci.themes.Liquid
	[ "$$(uci -q get luci.main.mediaurlbase)" = "/luci-static/liquid" ] && \
		uci -q delete luci.main.mediaurlbase
	uci commit luci
}
exit 0
endef

# 版本迭代：改 PKG_RELEASE（r 值）时，同步更新
# ucode/template/themes/liquid/VERSION（模板用它做 foot 显示与 ?v= 缓存破坏）。
include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
