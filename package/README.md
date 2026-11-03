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
gen5-autolock.conf.example   the documented settings template
gen5-autolock.conf.seed      written by the build: DRY_RUN=0 (standard) or 1 (test-mode)
                             — copied to /data/nemesis/gen5-autolock.conf on a FRESH install
ref/README.md                how the framework hash gate works / pinning another firmware
```

`NEMESIS.data` uses descriptor format **1.1** (NEMESIS 1.16: `package-version`,
`short-desc`, `os`, `models`, so it lists with the right compatibility colour in the
Package Store) and also carries the 1.0 `types=` key, so a unit still on NEMESIS 1.15
registers the service too.

## Build

```sh
tools/build-package.sh
#  -> dist/gen5-autolock-install.zip           USB installer, LIVE from the next stop
#  -> dist/gen5-autolock-install-testmode.zip  USB installer, TEST MODE (log only)
#  -> dist/gen5.autolock.zip                   bare LIVE package (shell install / Package Store)
```

Needs `zip` or a working Python. The two installer zips are finished USB sticks: extract
one to the root of a stick and insert. They differ only in the seeded `DRY_RUN` value.

## Install (USB)

Each installer stick is just these two files at the **root** of the stick:

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
`/data/nemesis/apps/gen5.autolock/`, seeds `/data/nemesis/gen5-autolock.conf` from the
package's seed (standard installer: `DRY_RUN=0`, **live from the next stop**; test-mode
installer: `DRY_RUN=1`, log only), and starts the service. The install hook prints which
mode it ended up in. Re-inserting a newer zip with the same id gives an update prompt;
your `/data/nemesis/gen5-autolock.conf` — settings **and** mode — is kept.

## Use it from the NEMESIS Manager

Open the Manager (triple-press the **Nav** button). Two ways to control it:

- **Services → `autolock` → Start / Stop** — the Services list shows its running/stopped
  state, so this is a toggle *with visible status*. Stop disables it for the session;
  it starts again on the next boot.
- **Packages → Gen5 Auto-Lock → Launch** — runs `toggle.sh`, which flips a persistent
  pause flag (`/data/nemesis/gen5-autolock.off`). This survives reboots: paused stays
  paused until you Launch again to resume.

## Modes and the framework gate

LIVE vs TEST MODE is a line in `/data/nemesis/gen5-autolock.conf` (`DRY_RUN=0` / `1`);
the GO LIVE and TEST MODE USB sticks flip it, the custom-settings stick changes the
delay. The daemon's built-in default is `DRY_RUN=1`, so a missing config never locks.

The hash gate passes by itself on a verified build (2022 US EV6, firmware 260507 — md5s
built into the script). On any other firmware it logs `FATAL: framework is not a verified
build …` and exits (fail-safe) until you pin your own odex into
`/data/nemesis/gen5-autolock-ref/` (outside the package tree, so an update won't wipe it)
— the **ref-odex** stick (`usb-sticks/ref-odex/`) does that with one tap and restarts the
service — or set `CHECK_ODEX=0`. See `ref/README.md`. Check the log on first install.

## Uninstall

```sh
nemesis uninstall gen5.autolock
```

Stops the service, removes the package, clears the pause flag; leaves your config and
log under `/data/nemesis/` (delete them by hand if you want them gone).
