# NEMESIS package (`gen5.autolock`)

This is the normal way to install gen5-autolock. Packaging it as a NEMESIS package
means NEMESIS **starts it at every boot** (via its service manager — no `/system`
init hacking) and gives you an **on-screen toggle in the NEMESIS Manager**.

## What's in the package

Built from the repo by `build-package.sh`, which assembles this tree and zips it:

```
NEMESIS.data                 declares the service + the toggle app + lifecycle hooks
walkaway.sh                  the daemon (service.0, kind=sh, mode=background)
bin/toggle.sh                the toggle app (app.0) — pause/resume
scripts/{pre,post,preun,postun}.sh   install/uninstall hooks
gen5-autolock.conf.example   seeded to /data/nemesis/gen5-autolock.conf on install
ref/README.md                where you drop your own odex for the hash gate
```

## Build

```sh
./build-package.sh            # -> gen5.autolock.zip  (needs `zip`)
```

## Install (USB)

Put this `NEMESIS.data` at the **root** of a USB stick next to the built zip:

```ini
[nemesis]
version=1.0
type=install
path=gen5.autolock.zip
```

```
<stick root>/
  NEMESIS.data
  gen5.autolock.zip
```

Insert the stick, confirm the install prompt. (Or from a shell:
`nemesis install /storage/usb0/gen5.autolock.zip`.) It installs to
`/data/nemesis/apps/gen5.autolock/`, seeds `/data/nemesis/gen5-autolock.conf`, and
starts the service — **in dry-run**. Re-inserting a newer zip with the same id gives
an update prompt; your `/data/nemesis/gen5-autolock.conf` is kept.

## Use it from the NEMESIS Manager

Open the Manager (triple-press the **Nav** button). Two ways to control it:

- **Services → `autolock` → Start / Stop** — the Services list shows its running/stopped
  state, so this is a toggle *with visible status*. Stop disables it for the session;
  it starts again on the next boot.
- **Packages → Gen5 Auto-Lock → Launch** — runs `toggle.sh`, which flips a persistent
  pause flag (`/data/nemesis/gen5-autolock.off`). This survives reboots: paused stays
  paused until you Launch again to resume.

## Arm it (leave dry-run first)

Edit `/data/nemesis/gen5-autolock.conf`: watch `/data/nemesis/gen5-autolock.log` across
a few real drives to confirm it only *would* fire on a genuine park-and-exit, then set
`DRY_RUN=0`. The hash gate expects your odex in `/data/nemesis/gen5-autolock-ref/`
(created on install; it lives outside the package tree so an update won't wipe it) — or
set `CHECK_ODEX=0`. See `ref/README.md`. **Until you do one of those the daemon refuses to
run**: it logs `FATAL: reference odex missing … — refusing to run` and exits (fail-safe),
so check the log on first install.

## Uninstall

```sh
nemesis uninstall gen5.autolock
```

Stops the service, removes the package, clears the pause flag; leaves your config and
log under `/data/nemesis/` (delete them by hand if you want them gone).
