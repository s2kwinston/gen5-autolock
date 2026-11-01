# Persistence — starting the daemon at boot

The daemon has to be running **before you switch the car off**, so it must start on
every head-unit boot.

## Recommended: install it as a NEMESIS package

The normal way is to install gen5-autolock as a **NEMESIS package** — then NEMESIS's
own service manager starts it at every boot and you don't touch `/system` yourself.
This is the supported mechanism and it's what the catalog packages use.

- The package registers the daemon as a **service** (`mode=background`: started once
  per boot, no auto-restart — which matches the daemon exiting cleanly when the head
  unit powers down).
- NEMESIS's watchdog (launched at cold boot and QuickBoot) starts the service manager,
  which starts registered services. So the daemon comes up on its own each drive.
- You can enable/disable it from the **NEMESIS Manager** (Services → `autolock` →
  Start/Stop) or pause/resume it (Packages → Launch).

Build and install: see [`../package/README.md`](../package/README.md).

## Manual alternatives (only if you're not using the package)

If you run `walkaway.sh` standalone instead of installing the package, something still
has to launch it each boot. Options, in rough order of preference:

1. **A NEMESIS run-script / your own init hook** that backgrounds it:
   ```sh
   sh /path/to/walkaway.sh >/dev/null 2>&1 &
   ```
2. **Piggyback an existing boot hook** on your setup.
3. **USB stick present at boot** — fragile and not recommended for a locking daemon.

However it starts, it writes to `/data/nemesis/gen5-autolock.log` (a persistent path —
`/data/local/tmp` is wiped on reboot), waits for `sys.boot_completed`, runs the optional
framework hash gate, then polls. With `DRY_RUN=1` (default) it only logs what it *would*
do — leave it there until the log looks right across several real drives, then set
`DRY_RUN=0`.

## Undo

Uninstall the package (`nemesis uninstall gen5.autolock`) — or remove whatever manual
hook you added. A locking daemon is exactly the kind of thing you want to switch off
quickly.
