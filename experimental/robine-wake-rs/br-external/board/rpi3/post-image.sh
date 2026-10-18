#!/bin/bash
# Raspberry Pi 3 post-image: signed firmware update, SD card image and the
# QEMU raspi3b launcher (OPS-001, QA-003).
set -e

BOARD_DIR=$(cd "$(dirname "$0")" && pwd)
FWUP="$HOST_DIR/bin/fwup"
KEY_DIR=${ROBINE_FWUP_KEY_DIR:-$BOARD_DIR/../../../output/keys}
export ROBINE_FW_VERSION=${ROBINE_FW_VERSION:-0.0.0-dev}

cd "$BINARIES_DIR"
"$BOARD_DIR/gen-fwup-conf.sh" "$BINARIES_DIR" "$BOARD_DIR" > fwup.conf
"$FWUP" -c -f fwup.conf -o robine-wake-unsigned.fw
"$FWUP" -S -s "$KEY_DIR/fwup-key.priv" -i robine-wake-unsigned.fw -o robine-wake.fw
rm -f robine-wake-unsigned.fw

# Image for dd or Raspberry Pi Imager. Flashing robine-wake.fw with fwup
# instead lets /data expand to the whole card.
rm -f sdcard.img
"$FWUP" -a -q -i robine-wake.fw -t complete -d sdcard.img
echo "robine-wake.fw $ROBINE_FW_VERSION: $(stat -c %s robine-wake.fw) bytes"

# QEMU boots the kernel directly, without the GPU firmware that applies the
# config.txt overlays: pre-apply disable-bt so ttyAMA0 is the serial console.
mkdir -p qemu
"$BUILD_DIR"/linux-custom/scripts/dtc/fdtoverlay \
	-i bcm2710-rpi-3-b-plus.dtb -o qemu/rpi3.dtb \
	rpi-firmware/overlays/disable-bt.dtbo
install -m 0755 "$BOARD_DIR/run-qemu.sh" run-qemu.sh
