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

# bluez-alsa 5 (package/bluez-alsa5) renamed its tools. Incremental builds keep
# the files of the previously selected 4.x package, so drop them.
if [ -x "$TARGET_DIR/usr/bin/bluealsad" ]; then
    rm -f "$TARGET_DIR/usr/bin/bluealsa" \
        "$TARGET_DIR/usr/bin/bluealsa-cli" \
        "$TARGET_DIR/usr/bin/a2dpconf" \
        "$TARGET_DIR/etc/dbus-1/system.d/bluealsa.conf" \
        "$TARGET_DIR/usr/share/dbus-1/system.d/bluealsa.conf"
fi

# Create the fwup ops script to handling MicroSD/eMMC operations at runtime
# NOTE: revert.fw is the previous, more limited version of this. ops.fw is
#       backwards compatible.
mkdir -p $TARGET_DIR/usr/share/fwup
$HOST_DIR/usr/bin/fwup -c -f $NERVES_DEFCONFIG_DIR/fwup-ops.conf -o $TARGET_DIR/usr/share/fwup/ops.fw
ln -sf ops.fw $TARGET_DIR/usr/share/fwup/revert.fw

# Copy the fwup includes to the images dir
cp -rf $NERVES_DEFCONFIG_DIR/fwup_include $BINARIES_DIR
