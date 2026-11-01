#!/system/bin/sh
# postuninstall — copied to tmp and run after the package tree is deleted.
# Clear the pause flag so a future reinstall doesn't start out paused. Leave the
# user's config and log in place (delete them yourself if you want them gone).
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
rm -f /data/nemesis/gen5-autolock.off 2>/dev/null
echo "gen5-autolock removed. Kept /data/nemesis/gen5-autolock.conf and .log."
exit 0
