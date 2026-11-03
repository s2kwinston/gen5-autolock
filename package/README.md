# NEMESIS package (`gen5.autolock`)

This is the normal way to install gen5-autolock. Packaging it as a NEMESIS package
means NEMESIS **starts it at every boot** (via its service manager — no `/system`
init hacking) and gives you an **on-screen toggle in the NEMESIS Manager**.

## What's in the package

Built from the repo by `tools/build-package.sh`, which assembles this tree and zips it:

```
NEMESIS.data                 declares the service + the toggle app + lifecycle hooks
walkaway.sh                  the daemon (service.0, kind=sh, mode=background)
bin/toggle.sh                the toggle app (app.0) — pause/resume
scripts/{pre,post,preun,postun}.sh   install/uninstall hooks
gen5-autolock.conf.example   seeded to /data/nemesis/gen5-autolock.conf on install
ref/README.md                where you drop your own odex for the hash gate
```

`NEMESIS.data` uses descriptor format **1.1** (NEMESIS 1.16: `package-version`,
`short-desc`, `os`, `models`, so it lists with the right compatibility colour in the
Package Store) and also carries the 1.0 `types=` key, so a unit still on NEMESIS 1.15
registers the service too.

## Build

```sh
tools/build-package.sh    # -> dist/gen5.autolock.zip + dist/gen5-autolock-install.zip
```

Needs `zip` or a working Python. `dist/gen5-autolock-install.zip` is the finished USB
stick: extract it to the root of a stick and insert. (It's just the two files below.)

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
`DRY_RUN=0`. The hash gate passes by itself on a verified build (2022 US EV6, firmware
260507 — md5s built into the script). On any other firmware it logs `FATAL: framework is
not a verified build …` and exits (fail-safe) until you pin your own odex into
`/data/nemesis/gen5-autolock-ref/` (outside the package tree, so an update won't wipe it)
— the **ref-odex** stick (`usb-sticks/ref-odex/`) does that with one tap and restarts the
service — or set `CHECK_ODEX=0`. See `ref/README.md`. Check the log on first install.

## Uninstall

```sh
nemesis uninstall gen5.autolock
```

Stops the service, removes the package, clears the pause flag; leaves your config and
log under `/data/nemesis/` (delete them by hand if you want them gone).
