#!/system/bin/sh
# gen5-autolock — apply settings from a USB stick.
# NEMESIS runs this (type=execute) when you insert the stick. It MERGES the
# KEY=value lines set in the gen5-autolock.conf next to it into the live config
# (/data/nemesis/gen5-autolock.conf): a key that exists there is replaced in place,
# a new key is appended, and every other line — your LIVE/TEST mode, other knobs,
# comments — is kept exactly as it was. Then it restarts the autolock service so
# the change takes effect now. It makes NO other change to the car.
# Toolbox/mksh only — no printf.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 077

SELF=${0%/*}
SRC="$SELF/gen5-autolock.conf"
DST=${GEN5_CONF:-/data/nemesis/gen5-autolock.conf}
LOG=${GEN5_LOG:-/data/nemesis/gen5-autolock.log}

say() { echo "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [apply-config] $*" >> "$LOG" 2>/dev/null; }
# write one line WITHOUT printf (this HU has none). Config lines never start with
# '-' or contain a backslash, so echo reproduces them verbatim.
putline() { echo "$1"; }
# the stick's line for KEY (last one wins), or nothing
stick_line() {
    found=""
    while IFS= read -r l || [ -n "$l" ]; do
        case "$l" in "$1="*) found=$l ;; esac
    done < "$SRC"
    [ -n "$found" ] && echo "$found"
}

mkdir -p "${DST%/*}" 2>/dev/null

if [ ! -f "$SRC" ]; then
    say "ERROR: gen5-autolock.conf is not next to this script on the USB stick."
    say "       Nothing was changed. See README.txt on the stick."
    exit 1
fi

# which keys does the stick set? (uncommented KEY=value lines only)
KEYS=""
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        [A-Z]*=*) k=${line%%=*}; case " $KEYS " in *" $k "*) ;; *) KEYS="$KEYS $k" ;; esac ;;
    esac
done < "$SRC"
if [ -z "$KEYS" ]; then
    say "ERROR: the stick's gen5-autolock.conf sets nothing (every line is a comment)."
    say "       Remove the '#' in front of the setting you want to change. Nothing changed."
    exit 1
fi

TMP="$DST.new.$$"
: > "$TMP" || { say "ERROR: cannot write near $DST. Nothing changed."; exit 1; }
DONE=""
if [ -f "$DST" ]; then
    # keep every live line; replace the ones whose key the stick sets
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            [A-Z]*=*)
                k=${line%%=*}
                case " $KEYS " in
                    *" $k "*) putline "$(stick_line "$k")" >> "$TMP"; DONE="$DONE $k" ;;
                    *)        putline "$line" >> "$TMP" ;;
                esac ;;
            *) putline "$line" >> "$TMP" ;;
        esac
    done < "$DST"
fi
# keys the live file didn't have yet: append
for k in $KEYS; do
    case " $DONE " in *" $k "*) ;; *) putline "$(stick_line "$k")" >> "$TMP" ;; esac
done

# never install an empty/garbled config over a good one
if [ ! -s "$TMP" ]; then
    rm -f "$TMP"; say "ERROR: rewrite produced an empty file — nothing changed."; exit 1
fi
if mv "$TMP" "$DST"; then
    chmod 600 "$DST" 2>/dev/null
    MSG=""; for k in $KEYS; do MSG="$MSG $(stick_line "$k")"; done
    say "Applied:$MSG. Everything else was kept."
else
    rm -f "$TMP"; say "ERROR: could not update $DST. Nothing changed."; exit 1
fi

# Restart so the new settings take effect now. If the package isn't installed
# (standalone), the stop/start are no-ops and settings load on the next start.
nemesis service stop  gen5.autolock/autolock >/dev/null 2>&1
if nemesis service start gen5.autolock/autolock >/dev/null 2>&1; then
    say "Done. New settings are live now (and on every drive from here on)."
    say "You can remove the USB stick."
    exit 0
elif [ -d /data/nemesis/apps/gen5.autolock ]; then
    say "ERROR: the package is installed but the service did not restart — it is still"
    say "       using the OLD settings for this drive. Try again or reboot."
    exit 1
else
    say "NOTE: not installed as a package (standalone) — new settings load on the next"
    say "      start. You can remove the USB stick."
    exit 0
fi
