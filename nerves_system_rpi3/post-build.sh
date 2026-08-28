#!/bin/sh

set -e

# speaker-test is used by the application to generate the continuous pink-wind
# bed for evening breathing sessions. Buildroot can keep the previously
# installed alsa-utils target files when only a package sub-option changes, so
# ensure the selected binary is present in the final root filesystem.
if [ -x "$STAGING_DIR/usr/bin/speaker-test" ]; then
    install -D -m 0755 \
        "$STAGING_DIR/usr/bin/speaker-test" \
        "$TARGET_DIR/usr/bin/speaker-test"
fi

# Create the fwup ops script to handling MicroSD/eMMC operations at runtime
# NOTE: revert.fw is the previous, more limited version of this. ops.fw is
#       backwards compatible.
mkdir -p $TARGET_DIR/usr/share/fwup
$HOST_DIR/usr/bin/fwup -c -f $NERVES_DEFCONFIG_DIR/fwup-ops.conf -o $TARGET_DIR/usr/share/fwup/ops.fw
ln -sf ops.fw $TARGET_DIR/usr/share/fwup/revert.fw

# Copy the fwup includes to the images dir
cp -rf $NERVES_DEFCONFIG_DIR/fwup_include $BINARIES_DIR
