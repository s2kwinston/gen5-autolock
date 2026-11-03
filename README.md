# EV6 Walk-Away Auto-Lock

A small shell daemon that locks a Kia EV6 after you park, switch off, get out, and
walk away — the "walk-away lock" the US body module doesn't offer. It runs on the
head unit under [NEMESIS](https://github.com/xwtk/hmg_nemesis) root and talks to the
body-control module through the stock vehicle service.

> [!CAUTION]
> **THIS LOCKS A REAL CAR AND CANNOT TELL WHEN A KEY IS STILL INSIDE.**
> On the car it was built for it locked — and stayed locked — with the fob inside
> (tested). The head unit receives no fob-presence signal, so no software guard is
> possible. The emergency blade key is *inside* the fob.
> **Keep a spare key outside the car. Never run it with a person or pet inside.
> Pause it before a valet, a car wash, or sitting in the switched-off car.**
> The standard installer is **live from your next stop**; a test-mode installer
> (log only, never locks) exists if you'd rather watch it first. Read
> [Safety](#-safety--read-this-first) and the
> [FAQ of tested edge cases](#faq--the-edge-cases-and-what-actually-happens) first.

---

## ⚠️ Safety — read this first

- **Key-inside lockout risk.** The lock command this uses has **no key-inside
  interlock** on the test vehicle: it locks the car and keeps it locked even with a
  fob inside. The head unit gets **no fob-presence signal at all** — this was verified
  all the way down to the CAN protocol (see [`docs/design.md`](docs/design.md) §8), so
  a software guard is impossible. The mechanical blade key lives inside the fob, so a
  fob locked in is a real lockout. **Keep a spare key outside the car** if you run this.
- **No occupant awareness.** It can lock with a person or pet inside. The interior door
  handle still opens from within, so it is not entrapment — but never rely on this with
  an occupant.
- **Live from the first stop** with the standard installer. If you'd rather watch it
  first, use the **test-mode installer** (or the TEST MODE stick): the daemon then logs
  `WOULD FIRE` and sends **no** lock until you switch it to LIVE. The daemon's own
  built-in default is test mode, so a missing config can never make it lock.
- **Characterized on one specific setup.** Everything here was measured on a single
  2022 US EV6 (see [Compatibility](#compatibility)). Other model years, firmwares, or
  markets may lock differently or expose different transaction codes. **Re-verify on
  your own car before trusting it.** You are responsible for your vehicle.

---

## What it does

The EV6 **auto-unlocks when you switch it off** (with "Auto Unlock at Vehicle Off"
on). This daemon restores a walk-away lock on top of that:

> After you park, turn the car off, get out and close the door, it locks the car once,
> a short time later.

It only ever **locks**. It has no unlock path, never fights a lock you perform
yourself, fires at most once per stop (with a small bounded retry), and stands down
for the rest of that stop. It arms only after it has seen a real drive, so it can't be
fooled by the head unit waking as you walk up to the car.

## Downloads — which zip do I need?

Everything on the [Releases](https://github.com/s2kwinston/gen5-autolock/releases) page
is a USB stick in a zip. The routine is always the same: **extract the zip to the root of
an empty USB stick** (FAT32 or exFAT), start the car, wait for the screen to load, insert
the stick, tap **Yes**, remove it. You never need more than one at a time, and most
people only ever touch the first three.

| Zip | What it is | When you need it |
|---|---|---|
| `gen5-autolock-install.zip` | **The installer — ready to go.** Installs the daemon as a NEMESIS package; it starts by itself every time the car starts and is **LIVE from your next stop**. | Once. Re-insert a newer version to update; your settings and mode are kept. |
| `gen5-autolock-install-testmode.zip` | The same installer, but it starts in **TEST MODE** — runs and logs `WOULD FIRE`, never locks — until you insert the GO LIVE stick. | Instead of the one above, if you'd rather watch the log for a few stops first. |
| `gen5-autolock-go-live.zip` | Switches to **LIVE** — it really locks the car. | Once, after a few test-mode stops looked right in the log. |
| `gen5-autolock-test-mode.zip` | Switches back to **TEST MODE** — runs and logs, never locks. | Any time you want it to stop locking without uninstalling. |
| `gen5-autolock-custom-settings.zip` | Changes a setting — mainly the lock delay (`LOCK_DELAY=15`). Edit its text file on your computer first; **only the lines you set change**, LIVE/TEST mode stays. | When 30 s isn't the delay you want. |
| `gen5-autolock-get-log.zip` | **Read-only.** Copies the daemon's log and settings onto the stick so you can read them on a computer. Changes nothing. | When you want to see what it did, or something looks off. |
| `gen5-autolock-ref-odex.zip` | Accepts a car software version the daemon doesn't recognise (another model/firmware, or after a Kia update) so the safety gate lets it run. | **Only** if the log says `FATAL: framework is not a verified build`. On a 2022 US EV6 you won't need it. |

(The bare NEMESIS package, `gen5.autolock.zip`, is what's *inside* the installer zips; it's
built by `tools/build-package.sh` for `nemesis install` from a shell and for the Package
Store, and isn't a USB stick by itself.)

## How to use (plain-language walkthrough)

**Set it up — once.**
1. Get `gen5-autolock-install.zip` from the Releases page and extract it to the **root**
   of a USB stick. (It's the package zip plus a `type=install` `NEMESIS.data` — see
   [`package/README.md`](package/README.md).)
2. Start the car, wait for the screen to fully load, insert the stick, tap **Yes**.
3. That's it. It's installed, **starts by itself every time you start the car**, and is
   **live from your next stop**. On a verified car (2022 US EV6, firmware 260507) there is
   nothing else to do. On any other firmware it refuses to run until you consciously
   accept that firmware with the **REF ODEX** stick (`usb-sticks/ref-odex/`, see its
   `README.txt`).

**Every drive — automatic, no USB.**
4. Park, switch off, get out, close the door → it locks itself about `LOCK_DELAY` seconds
   later (30 by default). Nothing to insert. This keeps working across reboots.

**Prefer to watch it first?** Use `gen5-autolock-install-testmode.zip` in step 1 instead:
same package, but it starts in **TEST MODE** — runs every drive and writes `WOULD FIRE` to
`/data/nemesis/gen5-autolock.log` without locking. When you're happy, insert the
**GO LIVE** stick (`usb-sticks/go-live/`). The **TEST MODE** stick puts it back to
logging-only anytime.

**Change the timer / other settings — anytime.** Use the **custom-settings** stick
(`usb-sticks/custom-settings/`): edit `LOCK_DELAY=45` (etc.) in its text file and insert
it. That's a tiny settings update, *not* a reinstall; the setting sticks. Full steps are
on each stick's `README.txt`.

**Turn it off / pause.** Open the NEMESIS Manager (three quick presses of the **Nav**
button) → **My Packages → Gen5 Auto-Lock → Launch** to pause (it shows PAUSED on screen;
Launch again to resume), or **Services → `autolock` → Stop** to halt it (on NEMESIS 1.16.4+
it stays stopped until you press Start; on 1.15 it came back at the next boot). Or use the
**TEST MODE** stick (logs only), or `ENABLED=0` in the settings to disable it for good.

> ⚠️ Keep a **spare key outside the car** — it can lock a key inside (see
> [Safety](#-safety--read-this-first)).

## Compatibility

| | |
|---|---|
| Vehicle | 2022 US Kia EV6 GT-Line |
| Head unit | Gen5W AVNT (`tcc803x`), Android 4.4.2 (KitKat) |
| Firmware | `CV_E.USA.S5W_M.V015.012.260507` |
| Root | [NEMESIS](https://github.com/xwtk/hmg_nemesis) 1.15 or 1.16.x — tested on 1.15 and 1.16.4 |
| Lock path | `IBCMService.lockDoor(true)` over the MMCAN body relay |

Other EV6 variants *may* work, but the lock behavior — especially the key-inside
behavior — was only established on the setup above. Treat anything else as untested.

## How it works

A lightweight polling loop reads the body-control cache
(`dumpsys com.hkmc.micom.bcm`, which sends no CAN) and runs a small state machine:

```
BOOT ──first IGN-on──▶ DRIVING ──IGN off──▶ WAIT_EXIT ──driver exits,──▶ ARMED ──debounce──▶ lock once
  (stands down         (reset point)        (watch for    all closed,      (debounce    (fresh pre-check,
   until a drive)                            the exit)     unlocked)         counting)    then fire)
```

The single write is `service call com.hkmc.micom.bcm 5 i32 1` (`lockDoor(true)`),
and only after a fresh pre-check passes (ignition off, off-standby, every door, the
liftgate and the hood closed, currently unlocked, a driver-door exit observed, debounce
elapsed). Full
rationale, the measured facts it is built on, timing margins, and limitations are in
[`docs/design.md`](docs/design.md).

## Install

**Prerequisites:** NEMESIS root on a head unit matching
[Compatibility](#compatibility). A toolbox shell (KitKat `sh`) — no
`grep`/`awk`/`busybox` needed.

### Recommended: install it as a NEMESIS package

Packaging is the normal way, and it gives you two things for free: NEMESIS **starts
the daemon at every boot** (its own service manager — no `/system` init hacking), and
an **on-screen toggle in the NEMESIS Manager**.

```sh
tools/build-package.sh    # -> dist/gen5-autolock-install.zip (LIVE), -install-testmode.zip, gen5.autolock.zip
```

Extract `gen5-autolock-install.zip` to the root of a USB stick and insert it — it's the
package zip plus a `type=install` `NEMESIS.data` (full steps and the file contents in
[`package/README.md`](package/README.md)). It installs to
`/data/nemesis/apps/gen5.autolock/`, seeds your config at
`/data/nemesis/gen5-autolock.conf`, and starts the service — **live** (the standard
installer seeds `DRY_RUN=0`; `gen5-autolock-install-testmode.zip` seeds `DRY_RUN=1`, log
only). An update never touches an existing config, so your settings and mode are kept.

**Framework hash gate:** the daemon refuses to run unless the vehicle framework is one
the lock transaction was verified against (an OTA can move transaction codes and turn a
"lock" into something else). It compares the md5 of the live `automotive*.odex` with the
verified build(s) listed in the script — on a 2022 US EV6 on firmware 260507 that passes
with no setup. On any other firmware it logs `FATAL: framework is not a verified build`
and exits (fail-safe) until you consciously accept that firmware: insert the **ref-odex**
stick ([`usb-sticks/ref-odex/`](usb-sticks/ref-odex/)), which pins your head unit's own
odex into `/data/nemesis/gen5-autolock-ref/` (proprietary files, never shipped here) and
restarts the service — or set `CHECK_ODEX=0`. Check the log on first install. See
[`ref/README.md`](ref/README.md).

### Standalone (advanced)

You can also run `walkaway.sh` directly without the package — then you arrange your own
boot launch (something must start it on every head-unit boot, before you switch the car
off). The package is the supported path; standalone is for people who already have their
own boot hook.

## Configure

**You never edit the script.** Settings live in a config file at
`/data/nemesis/gen5-autolock.conf`, changed on the car (no PC plugged in, no shell) with
a USB stick from **[`usb-sticks/`](usb-sticks/)** — insert, tap Yes, done:

| Stick | What it does |
|---|---|
| `usb-sticks/go-live/` | Switch to LIVE (really locks). Keeps your other settings. |
| `usb-sticks/test-mode/` | Switch to TEST MODE (runs, logs, never locks). Keeps your other settings. |
| `usb-sticks/custom-settings/` | Edit the plain-text file (e.g. `LOCK_DELAY=15`) and insert — changes **only** the lines you set; your LIVE/TEST mode and other settings stay. |
| `usb-sticks/ref-odex/` | One-time after install: pins your head unit's own framework for the hash gate and starts the daemon. |

Each is a tiny settings update, not a reinstall, and it persists. One more stick,
**`usb-sticks/get-log/`**, changes nothing — it copies the log and a body-control snapshot
onto the USB for reading on a computer (and for the liftgate check — see
[Optional: test mode first](#optional-test-mode-first)). Pre-zipped copies for a Release are produced by
`tools/build-sticks.sh` (into `dist/`). (Running standalone? The daemon also reads a
`gen5-autolock.conf` next to `walkaway.sh`.)

Out-of-range or non-numeric values are ignored and the built-in default is used, so a
typo can't make it misbehave — and the file is **parsed, never executed**. The knobs:

| Knob | Default | Purpose |
|---|---|---|
| `LOCK_DELAY` | `30` | Seconds after the last door closes before locking, counted in real (wall-clock) seconds. Range 5–600, but **keep ≤ ~120**: the car only stays lockable ~178 s after the door closes (measured), so a bigger value can miss the lock entirely. |
| `DRY_RUN` | `1` built-in; the standard installer seeds `0` | `1` = log `WOULD FIRE`, send no lock. `0` = really lock. The GO LIVE / TEST MODE sticks flip it. |
| `ENABLED` | `1` | `0` = installed but inactive — stands down, never locks. |
| `DRIVER_DOOR_ONLY` | `1` | `1` = arm only on a driver-door exit; `0` = any door. |
| `POLL_ACTIVE` | `1` | Poll interval (s) after ignition off — 1 s catches a quick exit (1–10). |
| `POLL_DRIVE` | `5` | Poll interval (s) while driving / idle (1–30). |
| `POST_FIRE_CONFIRM` | `5` | Seconds to wait and recheck that the lock took (1–30). |
| `MAX_FIRES` | `3` | Lock attempts per stop before giving up (1–10; never hammers). |
| `MIN_ACC` | `3` | Only fire at this ACC state (off-standby). |
| `CHECK_ODEX` | `1` | `1` = refuse to run if the framework hash changed. |
| `HOOD_GUARD` | `1` | `1` = hold (don't lock) while the hood/frunk is open — read TX-free from the system log. `0` = ignore the hood. |

### Turn it on/off

**From the NEMESIS Manager** (three quick presses of the Nav button) — if you installed
the package:
- **My Packages → Gen5 Auto-Lock → Launch** — flips a persistent pause flag that
  **survives reboots** (stays paused until you Launch again). On NEMESIS 1.16+ the screen
  shows `PAUSED` / `RESUMED` so you know which way it went.
- **Services → `autolock` → Start / Stop** — shows running/stopped state; a toggle with
  visible status. On NEMESIS 1.16.4+ a stopped service **stays stopped** until you press
  Start (on 1.15 it came back at the next boot).

**From a shell** (either install mode), no restart needed:

```sh
touch /data/nemesis/gen5-autolock.off   # pause — stands down, won't lock
rm    /data/nemesis/gen5-autolock.off    # resume (re-arms on the next drive)
```

**Pause it before** you sit in the switched-off car with the key, hand it to a valet, or
drop it at service or a car wash — otherwise the fob gets left inside and it locks in. The
flag survives reboots. (`ENABLED=0` in the config disables it permanently.)

## Optional: test mode first

With the test-mode installer (or the TEST MODE stick), the daemon runs and logs but never
locks. It writes to
`/data/nemesis/gen5-autolock.log` (no shell? insert the **get-log** stick,
[`usb-sticks/get-log/`](usb-sticks/get-log/), to copy that log and a body-control
snapshot onto the USB). Over a few real stops, confirm:

- it logs `WOULD FIRE` **only** after a genuine park → off → exit → doors closed;
- it **never** logs `WOULD FIRE` at boot, while you are getting in, or with a door open;
- **liftgate and hood:** the daemon logs the raw values on its `exit seen …` and
  `ARMED …` lines (`trunk=1`, `hood=1`). Both are verified on the reference car; on any
  other car, open each and confirm the value appears — either on those lines (lid already
  open as you get out) or as a `… open — holding` line (opened *after* it armed; it should
  then resume when you close it). If one never leaves `0`, that guard is blind on your
  firmware (see [Limitations](#limitations)).

Once that log looks right, the **GO LIVE** stick switches it to locking.

## Limitations

- **Key inside / no occupant detection** — see [Safety](#-safety--read-this-first).
- **Time-based, not proximity-based** — it can't tell you walked *away* vs. stepped out
  and stood next to the car.
- **Only active while the head unit is awake** after switch-off — about 3½ minutes
  (measured). Sitting in the switched-off car is safe (no exit seen, nothing arms), but if
  you sit longer than that and then get out, the daemon is already gone and it won't lock
  — lock with the fob, same as stock.
- **Liftgate and hood are guarded; windows and sunroof are not.** It won't lock while the
  liftgate or the hood/frunk is open, and it holds (without needing a fresh exit) while
  you load cargo — both verified on the reference car (the hood is read from the system
  log, since it isn't in `dumpsys`). Confirm on your own car (see the check above). A
  **fob shut in the frunk** is still a lockout — the hood is closed by then, the car locks
  normally, and the frunk has no outside release. Keep the fob on you. Windows and the
  sunroof aren't read: it locks with them open, like stock.
- **Getting back in can lock you in.** Climbing back through the driver door after you'd
  gotten out reads as a fresh exit — it re-arms and locks with you inside after the delay.
  Pause it first (see [Turn it on/off](#turn-it-onoff)). The interior handle still opens a
  locked door from within.
- **Charging:** if you reach the charge port just as it locks, the port won't pop — you
  unlock, plug in, and it stays unlocked for the session (one lock per stop). Plug in
  first, or press LOCK after plugging in.

Full reasoning, the measured facts, and the detection analysis are in
[`docs/design.md`](docs/design.md) §8.

## FAQ — the edge cases, and what actually happens

Each answer says how it was established: **on-car** = observed on the 2022 US EV6 it
was built on; **measured** = from that car's own data; **by design** = the daemon's
logic, exercised on the bench against replayed car states (the real script, not a model).

- **I left the key inside.** It locks, and stays locked. **On-car.** This lock path has
  no key-inside interlock and the head unit gets no fob signal, so there is nothing to
  guard with. The blade key is inside the fob — keep a spare key outside the car.
- **Someone stays in the car after I get out.** It locks with them inside. The interior
  handle opens the door from within; doing so after the lock trips the alarm. **By
  design** — there is no occupant signal (measured: the seat-belt sensors never reach the
  head unit).
- **I park, switch off, and just sit there.** Nothing arms — it needs a driver-door
  open→close *after* switch-off. Get out within ~3½ minutes and it arms as normal; after
  that the head unit has gone to sleep and the daemon with it, so there is no auto-lock —
  lock with the fob, same as stock. **Measured** (unit awake 205 s after switch-off;
  lockable 178 s after the door closes).
- **I get out, then get back in.** It cannot tell re-entry from a fresh exit: when you
  close the driver door it re-arms and locks with you inside after the delay. **By
  design.** Pause it first (Manager → My Packages → Gen5 Auto-Lock → Launch, or the TEST
  MODE stick). The interior handle
  still opens the door.
- **I reopen a door during the countdown to grab something.** It drops back to waiting
  and needs a fresh driver-door close, then the full delay again. **By design.**
- **The liftgate is open when I get out, or I open it after.** It waits / holds, and
  resumes the countdown the moment the liftgate closes — no second exit needed. **On-car**,
  both shapes.
- **The frunk/hood is open.** Same hold, read from the head unit's system log (it isn't in
  the normal vehicle data). **On-car.** A fob *shut inside* the frunk is still a lockout —
  the hood is closed by then and the frunk has no outside release.
- **A window or the sunroof is open.** It locks anyway; the head unit has no usable
  window/sunroof value. **Measured.** Same as a stock lock.
- **I lock it myself first (fob or handle).** It sees the car is locked and stands down;
  it never double-sends. **By design.**
- **The head unit wakes as I walk up (approach unlock).** That is not a drive — it arms
  only after it has seen ignition on, so a boot-on-approach can never lock you in while
  you get seated. **By design.**
- **Quick stop — switch off, then restart without getting out.** Ignition on resets
  everything; nothing fires. **By design.**
- **Charging.** Plug in *before* it locks; if it locks first, the charge port won't pop —
  unlock, plug in, and it stays unlocked for that stop (one lock per stop). **By design**;
  not yet exercised on-car.
- **Kia pushes a software update.** It refuses to run (`FATAL: framework is not a
  verified build`) until you consciously re-pin — an update could renumber the lock
  command. **On-car** for the pass; the refusal path **by design**.
- **The head unit reboots mid-cycle.** The daemon restarts, stands down, and waits for
  the next drive; a reboot never produces a lock. **On-car** (every dry-run cycle began
  from a boot).
- **I set a very long delay.** The unit sleeps before it fires → no lock. The delay is
  clamped to 5–600 s; keep it ≤ ~120. **Measured.**
- **Valet, car wash, dealer.** Pause it first — otherwise a fob left with the car gets
  locked in the moment someone closes the door and walks off.
- **Does it ever unlock?** No. There is no unlock code in the daemon: the only vehicle
  write is the single lock command, and every bench scenario asserts no unlock is ever
  sent. **By design.**
- **Will the alarm arm?** Yes, like any lock: the car arms ~30 s after locking; opening a
  door from inside after that trips it. **On-car.**

## License

[MIT](LICENSE).

## Disclaimer

Not affiliated with, endorsed by, or connected to Kia or Hyundai. This is an
independent modification for a rooted head unit. It controls vehicle locks and is
provided with no warranty of any kind. Rooting your head unit and automating vehicle
functions is entirely at your own risk and may affect your warranty. **You are
responsible for your vehicle and anything locked inside it.**
