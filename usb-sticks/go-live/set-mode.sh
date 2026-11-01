#!/system/bin/sh
# gen5-autolock — set run mode (LIVE vs TEST) from a USB stick.
# Reads the MODE file next to this script (0 = LIVE, 1 = TEST), flips ONLY the
# DRY_RUN line in the live config (keeping your lock-delay and other settings),
# then restarts the service. It makes NO other change to the car.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 077

SELF=${0%/*}
CFG=${GEN5_CONF:-/data/nemesis/gen5-autolock.conf}
LOG=${GEN5_LOG:-/data/nemesis/gen5-autolock.log}
say() { echo "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [set-mode] $*" >> "$LOG" 2>/dev/null; }
# write one line WITHOUT printf (this HU's toolbox/mksh has none). echo is a
# builtin on mksh and bash; our config lines never start with '-' or contain a
# backslash, so echo reproduces them verbatim.
putline() { echo "$1"; }

want=$(cat "$SELF/MODE" 2>/dev/null)
case "$want" in
    0) label="LIVE — it will really lock the car" ;;
    1) label="TEST MODE — runs and logs, never locks" ;;
    *) say "ERROR: bad MODE file (expected 0 or 1). Nothing changed."; exit 1 ;;
esac

mkdir -p "${CFG%/*}" 2>/dev/null
TMP="$CFG.new.$$"
found=0
if [ -f "$CFG" ]; then
    : > "$TMP" || { say "ERROR: cannot write near $CFG. Nothing changed."; exit 1; }
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            DRY_RUN=*) putline "DRY_RUN=$want" >> "$TMP"; found=1 ;;
            *)         putline "$line"         >> "$TMP" ;;
        esac
    done < "$CFG"
    [ "$found" = 1 ] || putline "DRY_RUN=$want" >> "$TMP"
else
    putline "DRY_RUN=$want" > "$TMP" || { say "ERROR: cannot create $CFG. Nothing changed."; exit 1; }
fi

# never install an empty/garbled config over a good one
if [ ! -s "$TMP" ]; then
    rm -f "$TMP"; say "ERROR: rewrite produced an empty file — nothing changed."; exit 1
fi

if mv "$TMP" "$CFG"; then
    chmod 600 "$CFG" 2>/dev/null
    say "Set DRY_RUN=$want  ->  $label. Your other settings were kept."
else
    rm -f "$TMP"; say "ERROR: could not update $CFG. Nothing changed."; exit 1
fi

# Restart so it takes effect now. If the package isn't installed (standalone),
# the stop/start are no-ops and the new mode loads on the next start anyway.
nemesis service stop  gen5.autolock/autolock >/dev/null 2>&1
if nemesis service start gen5.autolock/autolock >/dev/null 2>&1; then
    say "Done — new mode is active now. You can remove the USB stick."
    exit 0
elif [ -d /data/nemesis/apps/gen5.autolock ]; then
    say "ERROR: the package is installed but the service did not restart — the OLD mode"
    say "       is still active for this drive. Try again or reboot. Nothing else changed."
    exit 1
else
    say "NOTE: not installed as a package (standalone) — the new mode loads on the next"
    say "      start. You can remove the USB stick."
    exit 0
fi
