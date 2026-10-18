#!/bin/sh
# Raspberry Pi 3 post-build: firmware signing key and on-device fwup tasks.
set -e

TARGET_DIR=$1
BOARD_DIR=$(cd "$(dirname "$0")" && pwd)
FWUP="$HOST_DIR/bin/fwup"

# Ed25519 key pair for signed updates (OPS-001.1). Production builds point
# ROBINE_FWUP_KEY_DIR at a directory holding fwup-key.pub and fwup-key.priv;
# otherwise a development pair is generated once under output/keys.
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
	"$FWUP" -c -f "$BOARD_DIR/fwup-ops.conf" -o "$TARGET_DIR/usr/share/fwup/ops.fw"

chmod 0755 "$TARGET_DIR/usr/sbin/robine-fw" "$TARGET_DIR/usr/sbin/robine-update"
