#!/system/bin/sh
# gen5-autolock toggle — flips the pause flag the daemon checks each poll.
# Run it from NEMESIS Manager: My Packages -> Gen5 Auto-Lock -> Launch (NEMESIS 1.16+
# shows the line this prints on screen).
# Flag lives under /data/nemesis so it survives a reboot (the daemon stays
# installed and running either way; "paused" just means it won't lock).
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
OFF=${GEN5_OFF:-/data/nemesis/gen5-autolock.off}
mkdir -p "${OFF%/*}" 2>/dev/null
if [ -f "$OFF" ]; then
    rm -f "$OFF"; sync
    echo "gen5-autolock: RESUMED — auto-lock is ACTIVE"
else
    : > "$OFF"; sync
    echo "gen5-autolock: PAUSED — auto-lock will NOT fire until you resume"
fi
exit 0
