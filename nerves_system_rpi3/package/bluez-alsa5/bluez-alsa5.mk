################################################################################
#
# bluez-alsa5
#
# Buildroot's bluez-alsa package is 4.3.1; release 5 is needed for A2DP sink
# delay reporting (audio/video sync on the phone). Codec options mirror the
# upstream package.
#
################################################################################

BLUEZ_ALSA5_VERSION = 5.0.0
BLUEZ_ALSA5_SOURCE = bluez-alsa-$(BLUEZ_ALSA5_VERSION).tar.gz
BLUEZ_ALSA5_SITE = https://github.com/arkq/bluez-alsa/archive/v$(BLUEZ_ALSA5_VERSION)
BLUEZ_ALSA5_LICENSE = MIT
BLUEZ_ALSA5_LICENSE_FILES = LICENSE
BLUEZ_ALSA5_DEPENDENCIES = \
	alsa-lib bluez5_utils libglib2 sbc \
	host-libglib2 host-pkgconf host-python3

# git repo, no configure
BLUEZ_ALSA5_AUTORECONF = YES

BLUEZ_ALSA5_CONF_OPTS = \
	--enable-aplay \
	--enable-ctl \
	--disable-a2dpconf \
	--disable-hcitop \
	--disable-rfcomm \
	--disable-midi \
	--disable-msbc \
	--disable-ofono \
	--disable-systemd \
	--disable-upower \
	--disable-mp3lame \
	--disable-mpg123 \
	--disable-opus \
	--disable-debug-time \
	--disable-manpages \
	--with-alsaplugindir=/usr/lib/alsa-lib \
	--with-alsaconfdir=/etc/alsa/conf.d \
	--with-dbusconfdir=/usr/share/dbus-1/system.d

ifeq ($(BR2_PACKAGE_FDK_AAC),y)
BLUEZ_ALSA5_DEPENDENCIES += fdk-aac
BLUEZ_ALSA5_CONF_OPTS += --enable-aac
else
BLUEZ_ALSA5_CONF_OPTS += --disable-aac
endif

ifeq ($(BR2_PACKAGE_LIBOPENAPTX),y)
BLUEZ_ALSA5_DEPENDENCIES += libopenaptx
BLUEZ_ALSA5_CONF_OPTS += --with-libopenaptx --enable-aptx --enable-aptx-hd
else
BLUEZ_ALSA5_CONF_OPTS += --without-libopenaptx --disable-aptx --disable-aptx-hd
endif

$(eval $(autotools-package))
