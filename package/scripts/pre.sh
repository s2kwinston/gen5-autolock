#!/system/bin/sh
# preinstall — runs before the package tree is copied (cwd = staging dir).
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
mkdir -p /data/nemesis 2>/dev/null
exit 0
