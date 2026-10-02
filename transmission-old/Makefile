include $(TOPDIR)/rules.mk

# Transmission 4.1.3 needs a C++20-capable toolchain. The matching GCC 14
# runtime is packaged separately and kept private to Transmission so it never
# replaces Entware's global C++ runtime.

PKG_NAME:=transmission-old
PKG_VERSION:=4.1.3
PKG_RELEASE:=1

PKG_SOURCE:=transmission-$(PKG_VERSION).tar.xz
PKG_SOURCE_URL:=https://github.com/transmission/transmission/releases/download/$(PKG_VERSION)/
PKG_HASH:=ce7d2d8b101f7eb54bc3cf0bc55f52f7ebd4a25fa48e00bdca9a7e0fc02617da

PKG_MAINTAINER:=Daniel Golle <daniel@makrotopia.org>
PKG_LICENSE:=GPL-2.0-or-later
PKG_LICENSE_FILES:=COPYING
PKG_CPE_ID:=cpe:/a:transmissionbt:transmission

PKG_INSTALL:=1
PKG_BUILD_DEPENDS:=libb64 libdht
PKG_BUILD_PARALLEL:=1
PKG_BUILD_FLAGS:=gc-sections lto
PKG_CONFIG_DEPENDS:= \
	CONFIG_LIBCURL_GNUTLS \
	CONFIG_LIBCURL_MBEDTLS \
	CONFIG_LIBCURL_OPENSSL \
	CONFIG_LIBCURL_WOLFSSL \
	CONFIG_LIBCURL_NOSSL
PKG_UNPACK=xzcat $(DL_DIR)/$(PKG_SOURCE) | $(TAR) -C $(PKG_BUILD_DIR) --strip-components=1 -xf -

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk
include $(INCLUDE_DIR)/nls.mk

define Package/transmission-old/template
  SUBMENU:=BitTorrent
  SECTION:=net
  CATEGORY:=Network
  TITLE:=BitTorrent client
  URL:=https://www.transmissionbt.com
  DEPENDS:=+transmission-old-runtime +libcurl +libdeflate +libevent2 \
	   +libevent2-pthreads +libminiupnpc +libnatpmp +libpthread +libpsl \
	   +librt +libutp +zlib +LIBCURL_NOSSL:libmbedtls \
	   +LIBCURL_GNUTLS:libmbedtls +LIBCURL_MBEDTLS:libmbedtls
endef

define Package/transmission-old-runtime
  SUBMENU:=BitTorrent
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Private GCC runtime for Transmission 4.1+
  URL:=https://www.transmissionbt.com
endef

define Package/transmission-old-runtime/description
 Private GCC 14 runtime libraries required by Transmission 4.1+.
 They are isolated under /opt/lib/transmission-4.1 and do not replace
 Entware's global libstdc++, libgcc_s or libatomic.
endef

define Package/transmission-old-runtime/extra_provides
	echo "libstdc++.so.6"; \
	echo "libgcc_s.so.1"; \
	echo "libatomic.so.1";
endef

define Package/transmission-old-daemon
  $(call Package/transmission-old/template)
  TITLE+= (daemon)
  USERID:=transmission=224:transmission=224
endef

define Package/transmission-old-cli
  $(call Package/transmission-old/template)
  TITLE+= (utilities)
endef

define Package/transmission-old-remote
  $(call Package/transmission-old/template)
  TITLE+= (remote)
endef

define Package/transmission-old-web
  $(call Package/transmission-old/template)
  TITLE+= (webinterface)
  DEPENDS:=+transmission-old-daemon
  PKGARCH:=all
endef

define Package/transmission-old-daemon/description
 Transmission is a simple BitTorrent client.
 This package contains the daemon and its Entware service/configuration files.
endef

define Package/transmission-old-cli/description
 Command-line Transmission utilities: cli, create, edit and show.
endef

define Package/transmission-old-remote/description
 Remote-control command-line interface for a Transmission daemon.
endef

define Package/transmission-old-web/description
 Transmission web interface resources.
endef

define Package/transmission-old-daemon/conffiles
/opt/etc/transmission/settings.json
endef

TARGET_CXXFLAGS += -DHAVE_SIZE_T
comma:=,
TARGET_LDFLAGS := $(subst -Wl$(comma)-rpath=/opt/lib,-Wl$(comma)-rpath=/opt/lib/transmission-4.1,$(TARGET_LDFLAGS))
TARGET_LDFLAGS += -latomic -Wl,--as-needed

CMAKE_OPTIONS += \
	-DENABLE_CLI:BOOL=YES \
	-DENABLE_GTK:BOOL=NO \
	-DENABLE_QT:BOOL=NO \
	-DENABLE_MAC:BOOL=NO \
	-DENABLE_TESTS:BOOL=NO \
	-DENABLE_NLS:BOOL=NO \
	-DENABLE_UTP:BOOL=YES \
	-DRUN_CLANG_TIDY:BOOL=NO \
	-DUSE_SYSTEM_EVENT2:BOOL=YES \
	-DUSE_SYSTEM_DEFLATE:BOOL=YES \
	-DUSE_SYSTEM_DHT:BOOL=YES \
	-DUSE_SYSTEM_MINIUPNPC:BOOL=YES \
	-DUSE_SYSTEM_NATPMP:BOOL=YES \
	-DUSE_SYSTEM_UTP:BOOL=YES \
	-DUSE_SYSTEM_B64:BOOL=YES \
	-DUSE_SYSTEM_PSL:BOOL=YES \
	-DWITH_INOTIFY:BOOL=YES \
	-DWITH_KQUEUE:BOOL=NO \
	-DWITH_SYSTEMD:BOOL=NO \
	-DB64_INCLUDE_DIR=$(STAGING_DIR)/opt/include \
	-DB64_LIBRARY=$(STAGING_DIR)/opt/lib/libb64.a \
	-DDHT_INCLUDE_DIR=$(STAGING_DIR)/opt/include \
	-DDHT_LIBRARY=$(STAGING_DIR)/opt/lib/libdht.a \
	-DUTP_INCLUDE_DIR=$(STAGING_DIR)/opt/include \
	-DUTP_LIBRARY=$(STAGING_DIR)/opt/lib/libutp.so \
	$(if $(CONFIG_LIBCURL_NOSSL),-DWITH_CRYPTO=mbedtls) \
	$(if $(CONFIG_LIBCURL_GNUTLS),-DWITH_CRYPTO=mbedtls) \
	$(if $(CONFIG_LIBCURL_MBEDTLS),-DWITH_CRYPTO=mbedtls) \
	$(if $(CONFIG_LIBCURL_OPENSSL),-DWITH_CRYPTO=openssl) \
	$(if $(CONFIG_LIBCURL_WOLFSSL),-DWITH_CRYPTO=wolfssl)

define Package/transmission-old-runtime/install
	$(INSTALL_DIR) $(1)/opt/lib/transmission-4.1
	$(CP) $(TOOLCHAIN_DIR)/lib/libstdc++.so.6* $(1)/opt/lib/transmission-4.1/
	$(RM) $(1)/opt/lib/transmission-4.1/*-gdb.py
	$(CP) $(TOOLCHAIN_DIR)/lib/libgcc_s.so.1 $(1)/opt/lib/transmission-4.1/
	$(CP) $(TOOLCHAIN_DIR)/lib/libatomic.so.1* $(1)/opt/lib/transmission-4.1/
endef

define Package/transmission-old-daemon/install
	$(INSTALL_DIR) $(1)/opt/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/opt/bin/transmission-daemon $(1)/opt/bin/

	$(INSTALL_DIR) $(1)/opt/etc/init.d/
	$(INSTALL_BIN) files/S88transmission $(1)/opt/etc/init.d/

	$(INSTALL_DIR) $(1)/opt/etc/transmission/{blocklists,resume,torrents,watchdir}
	$(INSTALL_CONF) files/settings.json $(1)/opt/etc/transmission/

	$(INSTALL_DIR) $(1)/opt/etc/sysctl.d/
	$(INSTALL_CONF) files/transmission.sysctl $(1)/opt/etc/sysctl.d/20-transmission.conf
endef

define Package/transmission-old-cli/install
	$(INSTALL_DIR) $(1)/opt/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/opt/bin/transmission-cli \
			$(PKG_INSTALL_DIR)/opt/bin/transmission-create \
			$(PKG_INSTALL_DIR)/opt/bin/transmission-edit \
			$(PKG_INSTALL_DIR)/opt/bin/transmission-show \
			$(1)/opt/bin/
endef

define Package/transmission-old-remote/install
	$(INSTALL_DIR) $(1)/opt/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/opt/bin/transmission-remote $(1)/opt/bin/
endef

define Package/transmission-old-web/install
	$(INSTALL_DIR) $(1)/opt/share/transmission
	$(CP) $(PKG_INSTALL_DIR)/opt/share/transmission/public_html $(1)/opt/share/transmission/
endef

$(eval $(call BuildPackage,transmission-old-runtime))
$(eval $(call BuildPackage,transmission-old-daemon))
$(eval $(call BuildPackage,transmission-old-cli))
$(eval $(call BuildPackage,transmission-old-remote))
$(eval $(call BuildPackage,transmission-old-web))
