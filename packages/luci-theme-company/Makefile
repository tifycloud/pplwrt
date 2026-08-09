include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-company
PKG_VERSION:=25.12.5-company.2-rc4
PKG_RELEASE:=1
PKG_MAINTAINER:=CompanyWrt contributors
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-company
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=CompanyWrt full LuCI theme
  DEPENDS:=+luci-base +luci-theme-openwrt-2020
  PKGARCH:=all
endef

define Package/luci-theme-company/description
 Complete CompanyWrt navigation, forms, tables and application surfaces. The
 official OpenWrt 2020 theme remains installed as a recovery fallback.
endef

define Build/Compile
endef

define Package/luci-theme-company/install
	$(INSTALL_DIR) $(1)/www/luci-static/company
	$(CP) ./root/www/luci-static/company/* $(1)/www/luci-static/company/
	$(INSTALL_DIR) $(1)/usr/share/ucode/luci/template/themes/company
	$(CP) ./root/usr/share/ucode/luci/template/themes/company/* $(1)/usr/share/ucode/luci/template/themes/company/
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(CP) ./root/etc/uci-defaults/* $(1)/etc/uci-defaults/
	$(INSTALL_DIR) $(1)/usr/share/luci/theme/company
	$(CP) ./root/usr/share/luci/theme/company/* $(1)/usr/share/luci/theme/company/
endef

$(eval $(call BuildPackage,luci-theme-company))
