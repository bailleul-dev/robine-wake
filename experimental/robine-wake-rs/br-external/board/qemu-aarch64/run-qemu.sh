#!/bin/sh
# Boot the Robine Wake QEMU virt image (QA-003).
#   MEM=128 ./run-qemu.sh        simulate a smaller board
#   SSH_PORT / HTTP_PORT         host ports forwarded to 22 / 4000
# Leave QEMU with Ctrl-A X.
set -e

IMAGES=$(dirname "$(readlink -f "$0")")
HOST_BIN="$IMAGES/../host/bin"
QEMU=qemu-system-aarch64
[ -x "$HOST_BIN/qemu-system-aarch64" ] && QEMU="$HOST_BIN/qemu-system-aarch64"

exec "$QEMU" \
	-M virt -cpu cortex-a53 -smp "${SMP:-2}" -m "${MEM:-256}" \
	-nographic \
	-kernel "$IMAGES/Image" \
	-append "root=/dev/vda1 rootfstype=squashfs ro rootwait console=ttyAMA0" \
	-drive file="$IMAGES/disk.img",if=none,format=raw,id=hd0 \
	-device virtio-blk-device,drive=hd0 \
	-netdev user,id=net0,hostfwd=tcp::"${SSH_PORT:-2222}"-:22,hostfwd=tcp::"${HTTP_PORT:-4000}"-:4000 \
	-device virtio-net-device,netdev=net0 \
	-device i6300esb \
	-device virtio-rng-device \
	"$@"
