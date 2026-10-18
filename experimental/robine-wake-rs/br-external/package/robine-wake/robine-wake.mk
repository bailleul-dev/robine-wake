################################################################################
#
# robine-wake
#
################################################################################

ROBINE_WAKE_VERSION = local
ROBINE_WAKE_SITE = $(call qstrip,$(BR2_PACKAGE_ROBINE_WAKE_DIST_DIR))
ROBINE_WAKE_SITE_METHOD = local
ROBINE_WAKE_LICENSE = Proprietary

define ROBINE_WAKE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/bin/robine-wake $(TARGET_DIR)/usr/bin/robine-wake
	$(INSTALL) -D -m 0755 $(@D)/bin/robine-reboot $(TARGET_DIR)/usr/sbin/robine-reboot
	rm -rf $(TARGET_DIR)/usr/share/robine-wake
	mkdir -p $(TARGET_DIR)/usr/share/robine-wake
	cp -a $(@D)/web $(TARGET_DIR)/usr/share/robine-wake/web
	if [ -d $(@D)/sounds ]; then \
		cp -a $(@D)/sounds $(TARGET_DIR)/usr/share/robine-wake/sounds; \
	fi
	if [ -f $(@D)/authorized_keys ]; then \
		$(INSTALL) -D -m 0600 $(@D)/authorized_keys \
			$(TARGET_DIR)/etc/robine-wake/authorized_keys.default; \
	fi
endef

ifeq ($(BR2_PACKAGE_ROBINE_WAKE_DEV_MODE),y)
define ROBINE_WAKE_INSTALL_DEV_MODE
	touch $(TARGET_DIR)/etc/robine-wake/dev-mode
endef
else
define ROBINE_WAKE_INSTALL_DEV_MODE
	rm -f $(TARGET_DIR)/etc/robine-wake/dev-mode
endef
endif
ROBINE_WAKE_POST_INSTALL_TARGET_HOOKS += ROBINE_WAKE_INSTALL_DEV_MODE

$(eval $(generic-package))
