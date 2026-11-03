#!/system/bin/sh
# gen5-autolock — REF ODEX stick.
# Copies this head unit's OWN framework files (automotive.odex and
# automotive-service.odex) into /data/nemesis/gen5-autolock-ref/, which is what the
# daemon's framework hash gate (CHECK_ODEX=1) accepts as a PINNED reference, then
# restarts the service so the daemon runs now instead of at the next boot. Needed only
# when the live framework is not one of the daemon's verified builds (the log says
# "FATAL: framework is not a verified build"); on a verified build the gate passes alone.
# It changes NOTHING under /system and never locks or unlocks.
# Toolbox/mksh only — no printf.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 077

ND=/data/nemesis
REF=${GEN5_REF:-$ND/gen5-autolock-ref}
LOG=${GEN5_LOG:-$ND/gen5-autolock.log}
FW=${GEN5_FRAMEWORK:-/system/framework}
FILES="automotive.odex automotive-service.odex"

say() { echo "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [ref-odex] $*" >> "$LOG" 2>/dev/null; }

# Check everything BEFORE writing anything, so a half-done reference can't happen.
for f in $FILES; do
    [ -f "$FW/$f" ] || { say "ERROR: $FW/$f not found on this head unit. Nothing changed."; exit 1; }
done
mkdir -p "$REF" 2>/dev/null || { say "ERROR: cannot create $REF. Nothing changed."; exit 1; }

for f in $FILES; do
    if [ -f "$REF/$f" ]; then
        if cmp "$FW/$f" "$REF/$f" >/dev/null 2>&1; then
            say "$f: reference already matches the head unit — kept."
            continue
        fi
        label="REPLACED (the framework changed since this reference was taken)"
    else
        label="copied"
    fi
    # copy to a temp name, verify byte-for-byte, then move into place
    rm -f "$REF/$f.new"
    if cp "$FW/$f" "$REF/$f.new" && cmp "$FW/$f" "$REF/$f.new" >/dev/null 2>&1 && mv "$REF/$f.new" "$REF/$f"; then
        chmod 600 "$REF/$f" 2>/dev/null
        say "$f: $label -> $REF/"
    else
        rm -f "$REF/$f.new"
        say "ERROR: copying $f did not verify. Stopped; fix this before relying on the gate."
        exit 1
    fi
done
sync

# Restart so the daemon passes the gate now. If the package isn't installed
# (standalone), stop/start are no-ops and the reference is used at the next start.
nemesis service stop  gen5.autolock/autolock >/dev/null 2>&1
if nemesis service start gen5.autolock/autolock >/dev/null 2>&1; then
    say "Done — reference in place and the service restarted. You can remove the USB stick."
    say "      (The daemon's log should now show 'odex gate' passing, no FATAL line.)"
    exit 0
elif [ -d /data/nemesis/apps/gen5.autolock ]; then
    say "NOTE: reference in place, but the service did not restart — it will start at the"
    say "      next boot. Try again, or Services -> autolock -> Start in the NEMESIS Manager."
    exit 1
else
    say "NOTE: not installed as a package (standalone) — the reference is in place for the"
    say "      next start. You can remove the USB stick."
    exit 0
fi
