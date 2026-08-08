include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-company
PKG_VERSION:=25.12.5-company.1
PKG_RELEASE:=1
PKG_MAINTAINER:=CompanyWrt contributors
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-company
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=CompanyWrt visual theme assets
  DEPENDS:=+luci-base
  PKGARCH:=all
endef

define Package/luci-theme-company/description
 CompanyWrt accessible visual assets used by luci-app-company. The official
 LuCI rescue theme remains available as a recovery fallback.
endef

define Build/Compile
endef

define Package/luci-theme-company/install
	$(INSTALL_DIR) $(1)/www/luci-static/company/css
	$(CP) ./root/www/luci-static/company/css/* $(1)/www/luci-static/company/css/
	$(INSTALL_DIR) $(1)/usr/share/luci/theme/company
	$(CP) ./root/usr/share/luci/theme/company/* $(1)/usr/share/luci/theme/company/
endef

$(eval $(call BuildPackage,luci-theme-company))
