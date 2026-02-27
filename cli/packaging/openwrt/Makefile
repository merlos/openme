# OpenWrt package Makefile for openme
#
# Place this file at:
#   <your-feed-dir>/net/openme/Makefile
#
# Then add the feed to feeds.conf and run:
#   ./scripts/feeds update <feed>
#   ./scripts/feeds install openme
#   make package/openme/compile
#
# Requires OpenWrt 23.05+ with go 1.21 feed package available.

include $(TOPDIR)/rules.mk

PKG_NAME:=openme
PKG_VERSION:=0.1.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://codeload.github.com/merlos/openme/tar.gz/refs/tags/v$(PKG_VERSION)?
PKG_HASH:=skip

# The Go module (go.mod) lives in the cli/ subdirectory of the repo.
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)-$(PKG_VERSION)

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1

# golang-package.mk variables
GO_PKG:=github.com/merlos/openme
# Subdirectory of the unpacked archive that contains go.mod
GO_PKG_BUILD_SUBDIR:=cli
# Import path of the binary to build (relative to the module root)
GO_PKG_BUILD_PKG:=$(GO_PKG)/cmd/openme

include $(INCLUDE_DIR)/package.mk
include $(TOPDIR)/feeds/packages/lang/golang/golang-package.mk

define Package/openme
  SECTION:=net
  CATEGORY:=Network
  TITLE:=Single Packet Authorization server/client
  URL:=https://openme.merlos.org
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/openme/description
  openme is a lightweight SPA (Single Packet Authorization) tool.
  openme serve listens on a UDP port and temporarily opens a firewall
  rule when it receives a valid cryptographically-signed knock packet
  from an authorised client.

  To a port scanner the service port is always closed; only clients
  holding a valid Ed25519 private key can knock.

  This package includes both the server and client in a single binary.
endef

define Package/openme/conffiles
/etc/openme/config.yaml
endef

define Package/openme/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/openme $(1)/usr/bin/

	# Persistent config directory (config.yaml written by `openme init`)
	$(INSTALL_DIR) $(1)/etc/openme

	# procd init script
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/openme.init $(1)/etc/init.d/openme
endef

$(eval $(call GoBinPackage,openme))
$(eval $(call BuildPackage,openme))
