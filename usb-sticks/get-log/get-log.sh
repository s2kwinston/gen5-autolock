#!/system/bin/sh
# gen5-autolock — GET LOG stick.
# READ-ONLY: copies the daemon's log, its config and a one-shot body-control
# snapshot onto THIS USB stick, so you can read them on a computer. It changes
# NOTHING on the car and never locks or unlocks. The snapshot is a cache read
# (dumpsys) and sends no CAN. Toolbox/mksh only — no printf.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 022

SELF=${0%/*}
ND=/data/nemesis
LOG=${GEN5_LOG:-$ND/gen5-autolock.log}
CONF=${GEN5_CONF:-$ND/gen5-autolock.conf}

STAMP=$(date '+%Y%m%d-%H%M%S' 2>/dev/null)
[ -n "$STAMP" ] || STAMP=snapshot
DEST="$SELF/gen5-autolock-logs/$STAMP"

say() { echo "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [get-log] $*" >> "$LOG" 2>/dev/null; }

mkdir -p "$DEST" 2>/dev/null || { say "ERROR: cannot write to the USB stick. Nothing copied."; exit 1; }

# Copy BEFORE we log our own notes, so the pulled log reflects the daemon only.
cp "$LOG"  "$DEST/gen5-autolock.log"  2>/dev/null
cp "$CONF" "$DEST/gen5-autolock.conf" 2>/dev/null
cp -r "$ND/logs/gen5.autolock" "$DEST/service-log" 2>/dev/null
# Body-control snapshot: a CACHE read, sends NO CAN. Open the liftgate/doors
# first to capture them here (e.g. "mTrunkOpenedState: 1").
dumpsys com.hkmc.micom.bcm > "$DEST/bcm-snapshot.txt" 2>&1

say "Copied log + config + a body-control snapshot to: gen5-autolock-logs/$STAMP/ on the USB."
say "Done — remove the stick and open that folder on a computer."
exit 0
