################################################################################
#
# shairport-sync5
#
# Buildroot's shairport-sync package is 4.3.7, whose AirPlay 2 buffered-audio
# stream (used by iPhones) plays silence with iOS 26 sources. Release 5 is
# AirPlay 2 only in the configuration below: Avahi mDNS, OpenSSL, ALSA, and
# FFmpeg for both ALAC and AAC decoding.
#
################################################################################

SHAIRPORT_SYNC5_VERSION = 5.5.2
SHAIRPORT_SYNC5_SOURCE = shairport-sync-$(SHAIRPORT_SYNC5_VERSION).tar.gz
SHAIRPORT_SYNC5_SITE = https://github.com/mikebrady/shairport-sync/archive/refs/tags/$(SHAIRPORT_SYNC5_VERSION)
SHAIRPORT_SYNC5_LICENSE = MIT, BSD-3-Clause
SHAIRPORT_SYNC5_LICENSE_FILES = LICENSES
SHAIRPORT_SYNC5_DEPENDENCIES = \
	alsa-lib avahi ffmpeg libconfig libgcrypt libplist libsodium openssl \
	popt util-linux host-pkgconf host-vim

# 5.5.2 dereferences the metadata pipe name at startup even when metadata is
# disabled in the configuration file (metadata/pipe.c), so leave metadata out.
# git repo, no configure
SHAIRPORT_SYNC5_AUTORECONF = YES

SHAIRPORT_SYNC5_CONF_OPTS = \
	--with-airplay-2 \
	--with-ffmpeg \
	--with-alsa \
	--with-avahi \
	--without-tinysvcmdns \
	--with-ssl=openssl \
	--without-metadata \
	--with-stdout \
	--without-libdaemon \
	--without-soxr \
	--without-convolution \
	--without-dbus-interface \
	--without-mpris-interface \
	--without-mqtt-client

# configure insists on finding plistutil and xxd, but the build itself never
# runs plistutil; xxd comes from host-vim. Satisfy the check with a stub.
define SHAIRPORT_SYNC5_PLISTUTIL_STUB
	printf '#!/bin/sh\nexit 0\n' > $(HOST_DIR)/bin/plistutil
	chmod 0755 $(HOST_DIR)/bin/plistutil
endef
SHAIRPORT_SYNC5_PRE_CONFIGURE_HOOKS += SHAIRPORT_SYNC5_PLISTUTIL_STUB

define SHAIRPORT_SYNC5_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/shairport-sync \
		$(TARGET_DIR)/usr/bin/shairport-sync
	$(INSTALL) -D -m 0644 $(@D)/scripts/shairport-sync.conf \
		$(TARGET_DIR)/etc/shairport-sync.conf
endef

$(eval $(autotools-package))
