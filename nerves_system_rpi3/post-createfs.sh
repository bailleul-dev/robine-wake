#!/bin/sh

set -e

FWUP_CONFIG=$NERVES_DEFCONFIG_DIR/fwup.conf

# The generated configuration is checked in so Docker/Buildroot does not need
# an Elixir installation during the post-image phase. Regenerate it with
# `mix generate_fwup_conf` whenever fwup.conf.eex changes.
test -f "$FWUP_CONFIG"

# Run the common post-image processing for nerves
$BR2_EXTERNAL_NERVES_PATH/board/nerves-common/post-createfs.sh $TARGET_DIR $FWUP_CONFIG
