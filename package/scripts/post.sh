#!/system/bin/sh
# postinstall — runs after the tree is copied and the service registered.
# cwd = /data/nemesis/apps/gen5.autolock
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 077                      # anything we create is owner-only
ND=/data/nemesis
# gen5-autolock-ref/ lives OUTSIDE the package tree so user-supplied odex for the
# hash gate survives a package update (the tree under apps/<id> is wiped on update).
mkdir -p "$ND" "$ND/gen5-autolock-ref" 2>/dev/null

# Seed a persistent, update-surviving config the user can edit. Never clobber
# an existing one (keep their settings across updates). Lock it down: the daemon
# reads it as root, so it should not be group-/world-writable (defense in depth —
# the daemon also only parses known keys, never executes the file).
if [ ! -f "$ND/gen5-autolock.conf" ] && [ -f gen5-autolock.conf.example ]; then
    cp gen5-autolock.conf.example "$ND/gen5-autolock.conf"
    chmod 600 "$ND/gen5-autolock.conf" 2>/dev/null
fi

echo "gen5-autolock installed."
echo "  * SHIPS IN DRY-RUN — it logs 'WOULD FIRE' and sends NO lock. Watch"
echo "    $ND/gen5-autolock.log across a few real drives, then set DRY_RUN=0"
echo "    in $ND/gen5-autolock.conf to arm it."
echo "  * KEEP A SPARE KEY OUTSIDE THE CAR. There is no key-inside protection;"
echo "    it can lock a key inside. Never rely on it with a person/pet inside."
echo "  * Framework hash gate: put automotive.odex + automotive-service.odex in"
echo "    $ND/gen5-autolock-ref/ (survives updates), or set CHECK_ODEX=0 in the"
echo "    config. See ref/README.md."
echo "  * Toggle from NEMESIS Manager (triple-press Nav): Services -> autolock ->"
echo "    Start/Stop, or Packages -> Gen5 Auto-Lock -> Launch (pause/resume)."
exit 0
