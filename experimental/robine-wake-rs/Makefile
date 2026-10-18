# Robine Wake 2 — build entry point.
#
#   make image                 build the image for BOARD (default: qemu)
#   make qemu                  boot the QEMU image (Ctrl-A X to quit)
#   make deploy HOST=…         push only the daemon to a running dev image
#   make update HOST=…         signed A/B firmware update (BOARD=rpi3)
#   make menuconfig            tune the Buildroot configuration
#   make savedefconfig         write it back to br-external/configs
#   make test                  host tests of the Rust workspace

BOARD ?= qemu
HOST ?= robine-wake.local
SSH_PORT ?= 22
# Dev devices and VMs get their own known_hosts: images are rebuilt often.
SSH_OPTS ?= -o UserKnownHostsFile=$(abspath output/known_hosts) -o StrictHostKeyChecking=accept-new

BR_VERSION := 2026.02.3
BR_SHA256 := 5a59e7501b0b4ec52c41f4bfa79412320e0b37eae5f719605a258e8d0c6fc7fb
BR_TARBALL := buildroot-$(BR_VERSION).tar.xz

TOP := $(abspath .)
CACHE := $(TOP)/.cache
BR_DIR := $(CACHE)/buildroot-$(BR_VERSION)
OUT := $(TOP)/output/$(BOARD)
DIST := $(TOP)/output/dist
BR_MAKE := $(MAKE) -C $(BR_DIR) O=$(OUT) BR2_EXTERNAL=$(TOP)/br-external \
	BR2_DL_DIR=$(CACHE)/dl

ifeq ($(BOARD),rpi0)
RUST_TARGET := arm-unknown-linux-musleabihf
else
RUST_TARGET := aarch64-unknown-linux-musl
endif
DAEMON := $(TOP)/target/$(RUST_TARGET)/release/robine-wake
AUTHORIZED_KEYS ?= $(wildcard $(HOME)/.ssh/id_*.pub)

# Firmware version stamped by fwup (OPS-001); each build is distinct.
ifndef ROBINE_FW_VERSION
ROBINE_FW_VERSION := 0.1.0-$(shell date -u +%Y%m%d%H%M%S)-$(shell git rev-parse --short HEAD 2>/dev/null || echo nogit)
endif
export ROBINE_FW_VERSION

.PHONY: image dist daemon defconfig menuconfig savedefconfig qemu deploy update test clean distclean

image: dist $(OUT)/.config
	$(BR_MAKE) robine-wake-dirclean
	$(BR_MAKE)
	@ls -l $(OUT)/images

$(BR_DIR)/Makefile:
	mkdir -p $(CACHE)/dl
	[ -f $(CACHE)/dl/$(BR_TARBALL) ] || \
		curl -fL -o $(CACHE)/dl/$(BR_TARBALL) https://buildroot.org/downloads/$(BR_TARBALL)
	echo "$(BR_SHA256)  $(CACHE)/dl/$(BR_TARBALL)" | sha256sum -c -
	tar -xf $(CACHE)/dl/$(BR_TARBALL) -C $(CACHE)
	touch $@

$(OUT)/.config: br-external/configs/robine_$(BOARD)_defconfig | $(BR_DIR)/Makefile
	$(BR_MAKE) robine_$(BOARD)_defconfig

defconfig: | $(BR_DIR)/Makefile
	$(BR_MAKE) robine_$(BOARD)_defconfig

menuconfig: $(OUT)/.config
	$(BR_MAKE) menuconfig

savedefconfig: $(OUT)/.config
	$(BR_MAKE) savedefconfig BR2_DEFCONFIG=$(TOP)/br-external/configs/robine_$(BOARD)_defconfig

daemon:
	cargo build --release --locked --target $(RUST_TARGET) -p robine-daemon

# Staging directory installed by the robine-wake Buildroot package.
dist: daemon
	rm -rf $(DIST)
	mkdir -p $(DIST)/bin
	cp $(DAEMON) $(DIST)/bin/robine-wake
	cp $(dir $(DAEMON))robine-reboot $(DIST)/bin/robine-reboot
	cp -a ../../priv/web $(DIST)/web
	[ ! -d ../../priv/sounds ] || cp -a ../../priv/sounds $(DIST)/sounds
	$(if $(AUTHORIZED_KEYS),cat $(AUTHORIZED_KEYS) > $(DIST)/authorized_keys)

qemu:
	$(OUT)/images/run-qemu.sh

# Development images only (OPS-002): replaces the daemon without reflashing.
deploy: daemon
	ssh $(SSH_OPTS) -p $(SSH_PORT) root@$(HOST) 'cat > /data/dev/robine-wake.new && \
		chmod 0755 /data/dev/robine-wake.new && \
		mv /data/dev/robine-wake.new /data/dev/robine-wake && \
		touch /data/dev/enabled && sv restart robine-wake && sv status robine-wake' < $(DAEMON)

# Signed A/B firmware update of a running device (OPS-001, Raspberry Pi).
update:
	ssh $(SSH_OPTS) -p $(SSH_PORT) root@$(HOST) robine-update $(UPDATE_FLAGS) < $(OUT)/images/robine-wake.fw

test:
	cargo test --locked

clean:
	rm -rf $(OUT) $(DIST)

distclean:
	rm -rf $(TOP)/output $(TOP)/target
