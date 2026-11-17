#!/system/bin/sh
# postinstall — runs after the tree is copied and the service registered.
# cwd = /data/nemesis/apps/gen5.autolock
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 077                      # anything we create is owner-only
ND=${GEN5_ND:-/data/nemesis}
# gen5-autolock-ref/ lives OUTSIDE the package tree so a user-pinned odex for the
# hash gate survives a package update (the tree under apps/<id> is wiped on update).
mkdir -p "$ND" "$ND/gen5-autolock-ref" 2>/dev/null

# Seed a persistent, update-surviving config the user can edit. Never clobber an
# existing one (keeps their settings AND their LIVE/TEST mode across updates).
# gen5-autolock.conf.seed is written by the build: DRY_RUN=0 for the standard
# installer (live from the next stop), DRY_RUN=1 for the test-mode installer.
# The daemon's own built-in default is DRY_RUN=1, so no config = never locks.
# Lock it down: the daemon reads it as root (defense in depth — it is parsed for
# known keys, never executed).
if [ ! -f "$ND/gen5-autolock.conf" ]; then
    if [ -f gen5-autolock.conf.seed ]; then
        cp gen5-autolock.conf.seed "$ND/gen5-autolock.conf"
    elif [ -f gen5-autolock.conf.example ]; then
        cp gen5-autolock.conf.example "$ND/gen5-autolock.conf"
    fi
    chmod 600 "$ND/gen5-autolock.conf" 2>/dev/null
fi

# The key-sensor installer ships gen5-autolock.conf.force: settings it must switch on
# even on an UPDATE (which otherwise never touches your config). Its KEY=value lines
# are APPENDED, so they win (the daemon reads the last line for each key); your other
# settings and comments stay as they were. The plain installers have no .force file.
if [ -f gen5-autolock.conf.force ] && [ -f "$ND/gen5-autolock.conf" ]; then
    {
        echo ""
        echo "# ---- set by the key-sensor installer ----"
        while IFS= read -r fl || [ -n "$fl" ]; do
            case "$fl" in [A-Z]*=*) echo "$fl" ;; esac
        done < gen5-autolock.conf.force
    } >> "$ND/gen5-autolock.conf"
fi

# Stop a key reader left running by the PREVIOUS install. The daemon starts the reader
# once; an update replaces the files but not the running process, and the new reader
# would see its live lock and step aside. Only a process whose command line names
# key-reader.sh is touched (a pid in the lock file can have been reused). It releases
# its own lock on TERM; after kill -9 the lock's pid is dead and the next reader takes over.
KL="$ND/key-reader.lock"
rp=""; read rp _ < "$KL/owner" 2>/dev/null
case "$rp" in ''|*[!0-9]*) rp="" ;; esac
if [ -n "$rp" ] && [ -d "/proc/$rp" ]; then
    rc=$(cat "/proc/$rp/cmdline" 2>/dev/null)    # NUL-separated; the NULs drop out
    case "$rc" in
        *key-reader.sh*)
            kill "$rp" 2>/dev/null
            n=0; while [ -d "/proc/$rp" ] && [ "$n" -lt 4 ]; do sleep 1; n=$((n + 1)); done
            [ -d "/proc/$rp" ] && kill -9 "$rp" 2>/dev/null
            echo "Stopped the previous key reader (pid $rp). Restart the autolock service to start the new one."
            ;;
    esac
fi

# Report the mode the daemon will actually run in (last DRY_RUN / KEY_GATE line wins,
# like the daemon; nothing set = its built-in test mode, key sensor off).
MODE="TEST MODE (logs 'WOULD FIRE', sends NO lock)"
KG=0
if [ -f "$ND/gen5-autolock.conf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            DRY_RUN=0*) MODE="LIVE — it will lock the car from your next stop" ;;
            DRY_RUN=1*) MODE="TEST MODE (logs 'WOULD FIRE', sends NO lock)" ;;
            KEY_GATE=1*) KG=1 ;;
            KEY_GATE=*)  KG=0 ;;
        esac
    done < "$ND/gen5-autolock.conf"
fi

echo "gen5-autolock installed. Mode: $MODE"
if [ "$KG" = 1 ]; then
    echo "Key sensor: ON — remove this stick and plug the ESP32 key sensor into the USB port."
    echo "  * It locks only after your key tag was heard as you got out and then went"
    echo "    quiet (it left). Key still heard, tag not heard, or sensor offline = NO lock."
    echo "  * Still keep a spare key outside the car until you have tested it yourself."
    echo "    It has no occupant awareness: never rely on it with a person/pet inside."
else
    echo "Key sensor: OFF (KEY_GATE=0)."
    echo "  * KEEP A SPARE KEY OUTSIDE THE CAR. There is no key-inside protection;"
    echo "    it can lock a key inside. Never rely on it with a person/pet inside."
fi
echo "  * Switch modes any time with the GO LIVE / TEST MODE USB sticks; change the"
echo "    delay with the custom-settings stick. Log: $ND/gen5-autolock.log"
echo "  * Framework hash gate: runs as-is on a verified build (2022 US EV6, fw 260507)."
echo "    Other firmware: it refuses to run until you pin your own odex (ref-odex USB"
echo "    stick -> $ND/gen5-autolock-ref/) or set CHECK_ODEX=0. See ref/README.md."
echo "  * Pause/resume from NEMESIS Manager: My Packages -> Gen5 Auto-Lock -> Launch;"
echo "    or Services -> autolock -> Start/Stop."
exit 0
