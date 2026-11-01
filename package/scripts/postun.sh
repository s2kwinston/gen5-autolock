#!/system/bin/sh
# postuninstall — copied to tmp and run after the package tree is deleted.
# Clear the pause flag so a future reinstall doesn't start out paused. Leave the
# user's config and log in place (delete them yourself if you want them gone).
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
# On an UPDATE, NEMESIS runs the OLD package's postuninstall too (before copying
# the new tree). The incoming package is staged here during that window, so its
# presence means "update, not removal" — do nothing, or we'd silently un-pause a
# daemon the user deliberately paused. (Stage path confirmed via the Launchpad port.)
[ -d /data/local/tmp/nemesis/stage/gen5.autolock ] && exit 0
rm -f /data/nemesis/gen5-autolock.off 2>/dev/null
echo "gen5-autolock removed. Kept /data/nemesis/gen5-autolock.conf and .log."
exit 0
