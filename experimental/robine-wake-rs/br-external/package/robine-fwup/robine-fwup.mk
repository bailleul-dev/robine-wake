################################################################################
#
# robine-fwup
#
################################################################################

# Buildroot 2026.02 ships fwup 1.9.1, which only handles four primary MBR
# partitions; the A/B layout needs logical partitions (OPS-001).
ROBINE_FWUP_VERSION = 1.16.0
ROBINE_FWUP_SOURCE = fwup-$(ROBINE_FWUP_VERSION).tar.gz
ROBINE_FWUP_SITE = $(call github,fwup-home,fwup,v$(ROBINE_FWUP_VERSION))
ROBINE_FWUP_LICENSE = Apache-2.0
ROBINE_FWUP_LICENSE_FILES = LICENSE
ROBINE_FWUP_DEPENDENCIES = host-pkgconf libconfuse libarchive
HOST_ROBINE_FWUP_DEPENDENCIES = host-pkgconf host-libconfuse host-libarchive
ROBINE_FWUP_AUTORECONF = YES
ROBINE_FWUP_CONF_ENV = ac_cv_path_HELP2MAN=""
HOST_ROBINE_FWUP_CONF_ENV = ac_cv_path_HELP2MAN=""

$(eval $(autotools-package))
$(eval $(host-autotools-package))
