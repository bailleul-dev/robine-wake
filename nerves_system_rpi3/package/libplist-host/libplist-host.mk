################################################################################
#
# libplist-host
#
# Host build of libplist, only for its plistutil tool, which Shairport Sync 5
# runs at build time to embed its AirPlay 2 info plist. Buildroot has no
# host-libplist, so this mirrors package/libplist and shares its tarball.
#
################################################################################

LIBPLIST_HOST_VERSION = 2.7.0
LIBPLIST_HOST_SOURCE = libplist-$(LIBPLIST_HOST_VERSION).tar.bz2
LIBPLIST_HOST_SITE = https://github.com/libimobiledevice/libplist/releases/download/$(LIBPLIST_HOST_VERSION)
LIBPLIST_HOST_DL_SUBDIR = libplist
LIBPLIST_HOST_LICENSE = LGPL-2.1+
LIBPLIST_HOST_LICENSE_FILES = COPYING
HOST_LIBPLIST_HOST_DEPENDENCIES = host-pkgconf
HOST_LIBPLIST_HOST_CONF_OPTS = --without-cython

$(eval $(host-autotools-package))
