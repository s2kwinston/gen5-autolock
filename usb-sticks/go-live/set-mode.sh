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

want=$(cat "$SELF/MODE" 2>/dev/null)
case "$want" in
    0) label="LIVE — it will really lock the car" ;;
    1) label="TEST MODE — runs and logs, never locks" ;;
    *) say "ERROR: bad MODE file (expected 0 or 1). Nothing changed."; exit 1 ;;
esac

mkdir -p "${CFG%/*}" 2>/dev/null
TMP="$CFG.new.$$"
CR=$(printf '\r')
found=0
if [ -f "$CFG" ]; then
    : > "$TMP" || { say "ERROR: cannot write near $CFG. Nothing changed."; exit 1; }
    while IFS= read -r line || [ -n "$line" ]; do
        l=${line%"$CR"}
        case "$l" in
            DRY_RUN=*) printf '%s\n' "DRY_RUN=$want" >> "$TMP"; found=1 ;;
            *)         printf '%s\n' "$l"            >> "$TMP" ;;
        esac
    done < "$CFG"
    [ "$found" = 1 ] || printf '%s\n' "DRY_RUN=$want" >> "$TMP"
else
    printf '%s\n' "DRY_RUN=$want" > "$TMP" || { say "ERROR: cannot create $CFG. Nothing changed."; exit 1; }
fi

if mv "$TMP" "$CFG"; then
    chmod 600 "$CFG" 2>/dev/null
    say "Set DRY_RUN=$want  ->  $label. Your other settings were kept."
else
    rm -f "$TMP"; say "ERROR: could not update $CFG. Nothing changed."; exit 1
fi

# Best-effort restart so it takes effect now (ignored if the package isn't installed).
nemesis service stop  gen5.autolock/autolock >/dev/null 2>&1
nemesis service start gen5.autolock/autolock >/dev/null 2>&1

say "Done. You can remove the USB stick."
exit 0
