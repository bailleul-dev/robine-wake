# Project-specific Buildroot packages
include $(sort $(wildcard $(NERVES_DEFCONFIG_DIR)/package/*/*.mk))
