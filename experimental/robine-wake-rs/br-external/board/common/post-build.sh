#!/bin/sh
# Common post-build fixups for every Robine Wake image.
set -e

TARGET_DIR=$1

# runit services are supervised from inittab; drop the sysv duplicates.
rm -f "$TARGET_DIR/etc/init.d/S50dropbear"
# Unused BusyBox daemons.
rm -f "$TARGET_DIR/etc/init.d/S50crond"

# The rootfs is read-only: runsv state goes to /run (created by S05data).
for service in "$TARGET_DIR"/etc/service/*; do
	name=${service##*/}
	chmod 0755 "$service/run"
	ln -sfn "/run/runit/supervise.$name" "$service/supervise"
	if [ -d "$service/log" ]; then
		chmod 0755 "$service/log/run"
		ln -sfn "/run/runit/supervise.$name.log" "$service/log/supervise"
	fi
done
chmod 0755 "$TARGET_DIR"/etc/init.d/S05data "$TARGET_DIR"/etc/init.d/S06clock

# Persistent mount point and root's SSH keys on /data.
mkdir -p "$TARGET_DIR/data"
rm -rf "$TARGET_DIR/root/.ssh"
ln -sfn /data/ssh/root "$TARGET_DIR/root/.ssh"
chmod 0700 "$TARGET_DIR/root"
