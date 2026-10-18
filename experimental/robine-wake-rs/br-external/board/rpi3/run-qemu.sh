#!/bin/sh
# Boot the Raspberry Pi 3 SD card image in QEMU raspi3b (QA-003).
#
# QEMU has no Raspberry Pi GPU firmware, so this script plays its part: it
# reads autoboot.txt, picks the boot slot (or the [tryboot] slot once after a
# `reboot "0 tryboot"`), and boots that slot's kernel and cmdline.txt. The SD
# card persists across runs in sdcard-qemu.img; RESET=1 starts from a fresh
# copy of sdcard.img. Networking uses usb-net, not the LAN9514.
#
# Leave QEMU with Ctrl-A X.
set -e

IMAGES=$(dirname "$(readlink -f "$0")")
HOST_BIN="$IMAGES/../host/bin"
QEMU=qemu-system-aarch64
[ -x "$HOST_BIN/qemu-system-aarch64" ] && QEMU="$HOST_BIN/qemu-system-aarch64"
MTYPE="$HOST_BIN/mtype"
MCOPY="$HOST_BIN/mcopy"

# Partition offsets in 512-byte blocks (fwup-common.conf).
AUTOBOOT=2048
BOOT_2=34816
BOOT_3=165888

SD="$IMAGES/sdcard-qemu.img"
if [ "${RESET:-0}" = 1 ] || [ ! -f "$SD" ]; then
	cp "$IMAGES/sdcard.img" "$SD"
	# QEMU needs a power-of-two size; 1 GiB is also the smallest supported card.
	truncate -s 1G "$SD"
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

tryboot=0
while :; do
	"$MTYPE" -i "$SD@@$((AUTOBOOT * 512))" ::autoboot.txt | tr -d '\r' > "$WORK/autoboot.txt"
	section=all
	[ "$tryboot" = 1 ] && section=tryboot
	part=$(awk -v want="[$section]" '
		/^\[/ { current = $0; next }
		current == want && /^boot_partition=/ { sub(/.*=/, ""); print }
	' "$WORK/autoboot.txt")
	case "$part" in
		2) offset=$BOOT_2 ;;
		3) offset=$BOOT_3 ;;
		*) echo "run-qemu: unsupported boot_partition '$part'" >&2; exit 1 ;;
	esac
	"$MCOPY" -n -i "$SD@@$((offset * 512))" ::Image "$WORK/Image"
	"$MCOPY" -n -i "$SD@@$((offset * 512))" ::cmdline.txt "$WORK/cmdline.txt"
	echo "run-qemu: booting partition $part$([ "$tryboot" = 1 ] && echo ' (tryboot)')"

	"$QEMU" \
		-M raspi3b \
		-nographic -no-reboot \
		-kernel "$WORK/Image" \
		-dtb "$IMAGES/qemu/rpi3.dtb" \
		-append "$(cat "$WORK/cmdline.txt") dwc_otg.fiq_fsm_enable=0" \
		-drive file="$SD",if=sd,format=raw \
		-usb -device usb-net,netdev=net0 \
		-netdev user,id=net0,hostfwd=tcp::"${SSH_PORT:-2222}"-:22,hostfwd=tcp::"${HTTP_PORT:-4000}"-:4000 \
		"$@" | tee "$WORK/console.log"

	# A guest reboot ends QEMU (-no-reboot): emulate the firmware restart.
	grep -q "reboot: Restarting system" "$WORK/console.log" || break
	if grep -q "Restarting system with command '0 tryboot'" "$WORK/console.log"; then
		tryboot=1
	else
		tryboot=0
	fi
done
