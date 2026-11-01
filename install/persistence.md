# Persistence — starting the daemon at boot

The daemon has to be **running before you switch the car off**, so it must start on
every head-unit boot. The head unit boots when you unlock/approach the car, so a
process launched at boot is up through the whole drive and into the switch-off window.

No persistence mechanism is bundled, because it is a `/system`/init change that depends
on your NEMESIS setup and is its own decision to make. The options below are in rough
order of preference.

## Options

1. **init service / `init.d` hook (preferred).** Start the script at boot from an init
   service, the same class of mechanism other NEMESIS mods use. Clean and supervised,
   but it requires modifying `/system` (or the init ramdisk) — a change you should make
   deliberately and be able to undo.

2. **Piggyback an existing boot hook.** If your setup already runs a startup script at
   boot (for another NEMESIS mod), add a line there to launch `walkaway.sh` in the
   background. No new kind of `/system` change beyond what you already have.

3. **USB stick present at boot (not preferred).** NEMESIS can run a stick's payload at
   boot. This is fragile (leaves a stick in the port, and a stick present at boot runs
   as root with no prompt) and is not recommended for a locking daemon.

## However you start it

Launch it detached so it keeps running, e.g.:

```sh
sh /path/to/walkaway.sh >/dev/null 2>&1 &
```

It writes to `/data/local/tmp/gen5-autolock.log`. It waits for `sys.boot_completed`, runs
the optional framework hash gate, then enters its poll loop. With `DRY_RUN=1` (default)
it only logs what it *would* do — leave it there until the log looks right across
several real drives, then set `DRY_RUN=0`.

## Undo

Whatever mechanism you choose, keep it easy to reverse (remove the init service / the
added line / the stick). A locking daemon is exactly the kind of thing you want to be
able to switch off quickly.
