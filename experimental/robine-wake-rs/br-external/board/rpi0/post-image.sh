#!/bin/bash
# Raspberry Pi Zero 1 W post-image: signed firmware update and SD card image (OPS-001, PLT-005).
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

rm -f sdcard.img
"$FWUP" -a -q -i robine-wake.fw -t complete -d sdcard.img
echo "robine-wake.fw $ROBINE_FW_VERSION: $(stat -c %s robine-wake.fw) bytes"
