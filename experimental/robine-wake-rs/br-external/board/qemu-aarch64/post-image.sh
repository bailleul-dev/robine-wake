#!/bin/sh
# Assemble disk.img for QEMU virt and install the launcher next to it.
set -e

BOARD_DIR=$(dirname "$0")

# Empty data partition; S05data formats it again if it ever becomes unreadable.
rm -f "$BINARIES_DIR/data.ext4"
"$HOST_DIR/sbin/mkfs.ext4" -q -L robine-data "$BINARIES_DIR/data.ext4" 64M

support/scripts/genimage.sh -c "$BOARD_DIR/genimage.cfg"

install -m 0755 "$BOARD_DIR/run-qemu.sh" "$BINARIES_DIR/run-qemu.sh"
