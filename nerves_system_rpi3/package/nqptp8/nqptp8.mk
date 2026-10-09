################################################################################
#
# nqptp8
#
# NQPTP 1.2.8 for Shairport Sync 5 (package/shairport-sync5); Buildroot's
# nqptp package is 1.2.4. Same shared-memory interface version (10), same
# build; the daemon is started by RobineWake.AirPlay, not by an init script.
#
################################################################################

NQPTP8_VERSION = 1.2.8
NQPTP8_SOURCE = nqptp-$(NQPTP8_VERSION).tar.gz
NQPTP8_SITE = https://github.com/mikebrady/nqptp/archive/refs/tags/$(NQPTP8_VERSION)
NQPTP8_LICENSE = GPL-2.0
NQPTP8_LICENSE_FILES = LICENSE
NQPTP8_DEPENDENCIES = libconfig host-pkgconf
# git repo, no configure
NQPTP8_AUTORECONF = YES

define NQPTP8_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/nqptp $(TARGET_DIR)/usr/bin/nqptp
endef

$(eval $(autotools-package))
