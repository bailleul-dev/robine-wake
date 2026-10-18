#!/bin/sh
# Raspberry Pi Zero 1 W post-build: firmware signing key and on-device fwup tasks (OPS-001, PLT-005).
set -e

TARGET_DIR=$1
BOARD_DIR=$(cd "$(dirname "$0")" && pwd)
FWUP="$HOST_DIR/bin/fwup"

KEY_DIR=${ROBINE_FWUP_KEY_DIR:-$BOARD_DIR/../../../output/keys}
if [ ! -f "$KEY_DIR/fwup-key.pub" ]; then
	echo "Generating a development firmware signing key in $KEY_DIR"
	mkdir -p "$KEY_DIR"
	(cd "$KEY_DIR" && "$FWUP" -g)
	chmod 0600 "$KEY_DIR/fwup-key.priv"
fi
install -D -m 0644 "$KEY_DIR/fwup-key.pub" "$TARGET_DIR/etc/robine-wake/fwup-key.pub"

mkdir -p "$TARGET_DIR/usr/share/fwup"
ROBINE_BOARD_DIR=$BOARD_DIR ROBINE_FW_VERSION=${ROBINE_FW_VERSION:-0.0.0-dev} \
	"$FWUP" -c -f "$BOARD_DIR/../rpi3/fwup-ops.conf" -o "$TARGET_DIR/usr/share/fwup/ops.fw"

chmod 0755 "$TARGET_DIR/usr/sbin/robine-fw" "$TARGET_DIR/usr/sbin/robine-update"
