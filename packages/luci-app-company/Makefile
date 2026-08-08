include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-company
PKG_VERSION:=25.12.5-company.2-rc1
PKG_RELEASE:=1
PKG_MAINTAINER:=CompanyWrt contributors
PKG_LICENSE:=MIT

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-company
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=CompanyWrt operations dashboard
  DEPENDS:=+luci-base +luci-compat +luci-mod-admin-full +luci-theme-company +ubus +rpcd
  PKGARCH:=all
endef

define Package/luci-app-company/description
 Read-only configuration, build and routing overview with safe links to OpenWrt
 network, firewall, PBR, wireless and system administration pages.
endef

define Build/Compile
endef

define Package/luci-app-company/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/company
	$(CP) ./root/usr/lib/lua/luci/view/company/* $(1)/usr/lib/lua/luci/view/company/
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(CP) ./root/usr/share/luci/menu.d/* $(1)/usr/share/luci/menu.d/
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(CP) ./root/usr/share/rpcd/acl.d/* $(1)/usr/share/rpcd/acl.d/
	$(INSTALL_DIR) $(1)/etc/config
	$(CP) ./root/etc/config/* $(1)/etc/config/
	$(INSTALL_DIR) $(1)/usr/share/company
	$(CP) ./root/usr/share/company/* $(1)/usr/share/company/
endef

$(eval $(call BuildPackage,luci-app-company))
