#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
env_file=${ROBINE_ENV_FILE:-"$repo_root/.env"}

if [ -f "$env_file" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
fi

: "${ROBINE_FWUP_PRIVATE_KEY:?Set ROBINE_FWUP_PRIVATE_KEY to the protected fwup private key path}"

unsigned_firmware="_build/rpi3_dev/nerves/images/robine_wake.fw"
signed_firmware="_build/rpi3_dev/nerves/images/robine_wake-signed.fw"
public_key="rootfs_overlay/etc/robine-wake/fwup-key.pub"

MIX_TARGET=rpi3 mix firmware

platform=$(fwup -m --metadata-key meta-platform -i "$unsigned_firmware")
product=$(fwup -m --metadata-key meta-product -i "$unsigned_firmware")

if [ "$platform" != "rpi3" ] || [ "$product" != "robine_wake" ]; then
  printf '%s\n' "Refusing to sign incompatible firmware: product=$product platform=$platform" >&2
  exit 1
fi

fwup -S -s "$ROBINE_FWUP_PRIVATE_KEY" -i "$unsigned_firmware" -o "$signed_firmware"
fwup -V -p "$public_key" -i "$signed_firmware"

printf '%s\n' "Signed firmware: $signed_firmware"
shasum -a 256 "$signed_firmware"
