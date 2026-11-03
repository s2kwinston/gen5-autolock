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

# Report the mode the daemon will actually run in (last DRY_RUN line wins, like
# the daemon; nothing set = its built-in test mode).
MODE="TEST MODE (logs 'WOULD FIRE', sends NO lock)"
if [ -f "$ND/gen5-autolock.conf" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            DRY_RUN=0*) MODE="LIVE — it will lock the car from your next stop" ;;
            DRY_RUN=1*) MODE="TEST MODE (logs 'WOULD FIRE', sends NO lock)" ;;
        esac
    done < "$ND/gen5-autolock.conf"
fi

echo "gen5-autolock installed. Mode: $MODE"
echo "  * KEEP A SPARE KEY OUTSIDE THE CAR. There is no key-inside protection;"
echo "    it can lock a key inside. Never rely on it with a person/pet inside."
echo "  * Switch modes any time with the GO LIVE / TEST MODE USB sticks; change the"
echo "    delay with the custom-settings stick. Log: $ND/gen5-autolock.log"
echo "  * Framework hash gate: runs as-is on a verified build (2022 US EV6, fw 260507)."
echo "    Other firmware: it refuses to run until you pin your own odex (ref-odex USB"
echo "    stick -> $ND/gen5-autolock-ref/) or set CHECK_ODEX=0. See ref/README.md."
echo "  * Pause/resume from NEMESIS Manager: My Packages -> Gen5 Auto-Lock -> Launch;"
echo "    or Services -> autolock -> Start/Stop."
exit 0
