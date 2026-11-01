#!/system/bin/sh
# gen5-autolock — apply settings from a USB stick.
# NEMESIS runs this (type=execute) when you insert the stick. It copies the
# gen5-autolock.conf sitting next to it into place and restarts the autolock
# service so the new settings take effect. It makes NO other change to the car.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 077

SELF=${0%/*}
SRC="$SELF/gen5-autolock.conf"
DST=${GEN5_CONF:-/data/nemesis/gen5-autolock.conf}
LOG=${GEN5_LOG:-/data/nemesis/gen5-autolock.log}

say() { echo "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [apply-config] $*" >> "$LOG" 2>/dev/null; }

mkdir -p "${DST%/*}" 2>/dev/null

if [ ! -f "$SRC" ]; then
    say "ERROR: gen5-autolock.conf is not next to this script on the USB stick."
    say "       Nothing was changed. See README.txt on the stick."
    exit 1
fi

if ! cp "$SRC" "$DST"; then
    say "ERROR: could not write $DST. Nothing changed."
    exit 1
fi
chmod 600 "$DST" 2>/dev/null
say "New settings applied to $DST."

# Best-effort restart so the new settings take effect immediately. Ignored if the
# package isn't installed (e.g. standalone use) — settings still load on next start.
nemesis service stop  gen5.autolock/autolock >/dev/null 2>&1
nemesis service start gen5.autolock/autolock >/dev/null 2>&1

say "Done. New settings are live now (and on every drive from here on)."
say "You can remove the USB stick."
exit 0
