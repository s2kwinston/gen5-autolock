# EV6 Walk-Away Auto-Lock

A small shell daemon that locks a Kia EV6 after you park, switch off, get out, and
walk away — the "walk-away lock" the US body module doesn't offer. It runs on the
head unit under [NEMESIS](https://github.com/xwtk/hmg_nemesis) root and talks to the
body-control module through the stock vehicle service.

> ⚠️ **This locks a real car and, on the hardware it was built for, cannot tell when
> a key is still inside. Read [Safety](#-safety--read-this-first) before you run it.
> It ships in dry-run mode and sends no lock until you turn that off.**

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
- **Ships in dry-run.** `DRY_RUN=1` is the default: the daemon logs `WOULD FIRE` and
  sends **no** lock. Watch the log across several real drives and confirm it would only
  ever fire on a genuine park-and-exit before you set `DRY_RUN=0`.
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

## How to use (plain-language walkthrough)

**Set it up — once.**
1. Get `gen5.autolock.zip` (from the Releases page, or build it with `build-package.sh`),
   put it on a USB stick with a `type=install` `NEMESIS.data` (see
   [`package/README.md`](package/README.md)).
2. Start the car, wait for the screen to fully load, insert the stick, tap **Yes**.
3. It's now installed and **starts by itself every time you start the car.** It begins in
   **TEST MODE** — it runs and writes a log but **does not lock yet**.

**Switch it on for real — once, after you've watched it.**
4. Drive normally a few times. (It's just logging to `/data/nemesis/gen5-autolock.log`.)
5. When you're happy, insert the **GO LIVE** stick (`usb-sticks/go-live/`) and tap Yes.
   Now it locks for real. (The **TEST MODE** stick, `usb-sticks/test-mode/`, puts it back
   to logging-only anytime.)

**Every drive — automatic, no USB.**
6. Park, switch off, get out, close the door → it locks itself about `LOCK_DELAY` seconds
   later (30 by default). Nothing to insert. This keeps working across reboots.

**Change the timer / other settings — anytime.** Use the **custom-settings** stick
(`usb-sticks/custom-settings/`): edit `LOCK_DELAY=45` (etc.) in its text file and insert
it. That's a tiny settings update, *not* a reinstall; the setting sticks. Full steps are
on each stick's `README.txt`.

**Turn it off / pause.** Open the NEMESIS Manager (triple-press the **Nav** button) →
**Services → `autolock` → Stop** (starts again next boot), or **Packages → Launch** to
pause until you Launch again. Or use the **TEST MODE** stick (logs only), or `ENABLED=0`
in the settings to disable it for good.

> ⚠️ Keep a **spare key outside the car** — it can lock a key inside (see
> [Safety](#-safety--read-this-first)).

## Compatibility

| | |
|---|---|
| Vehicle | 2022 US Kia EV6 GT-Line |
| Head unit | Gen5W AVNT (`tcc803x`), Android 4.4.2 (KitKat) |
| Firmware | `CV_E.USA.S5W_M.V015.012.260507` |
| Root | [NEMESIS](https://github.com/xwtk/hmg_nemesis) |
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
and only after a fresh pre-check passes (ignition off, off-standby, every door and the
trunk closed, currently unlocked, a driver-door exit observed, debounce elapsed). Full
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
./build-package.sh                 # -> gen5.autolock.zip  (needs `zip`)
```

Put the zip + a `type=install` `NEMESIS.data` on a USB stick and insert it (full steps
and the file contents in [`package/README.md`](package/README.md)). It installs to
`/data/nemesis/apps/gen5.autolock/`, seeds your config at
`/data/nemesis/gen5-autolock.conf`, and starts the service **in dry-run**.

**Framework hash gate (recommended):** the daemon refuses to run if the vehicle
framework no longer matches what the lock transaction was verified against (an OTA can
move transaction codes and turn a "lock" into something else). Put your head unit's own
`automotive.odex` + `automotive-service.odex` in
`/data/nemesis/gen5-autolock-ref/` (they're proprietary and **not** shipped here),
or set `CHECK_ODEX=0` in the config. **Until you do one of those the daemon refuses to
run** — it logs a `FATAL: reference odex missing` line and exits (fail-safe), so check the
log on first install. See [`ref/README.md`](ref/README.md).

### Standalone (advanced)

You can also run `walkaway.sh` directly without the package — then you arrange your own
boot launch. See [`install/persistence.md`](install/persistence.md).

## Configure

**You never edit the script.** Settings live in a config file at
`/data/nemesis/gen5-autolock.conf`, changed on the car (no PC plugged in, no shell) with
a USB stick from **[`usb-sticks/`](usb-sticks/)** — insert, tap Yes, done:

| Stick | What it does |
|---|---|
| `usb-sticks/go-live/` | Switch to LIVE (really locks). Keeps your other settings. |
| `usb-sticks/test-mode/` | Switch to TEST MODE (runs, logs, never locks). Keeps your other settings. |
| `usb-sticks/custom-settings/` | Edit the plain-text file (e.g. `LOCK_DELAY=45`) and insert — sets any knob. |

Each is a tiny settings update, not a reinstall, and it persists. Pre-zipped copies for
a Release are produced by `build-sticks.sh`. (Running standalone? The daemon also reads a
`gen5-autolock.conf` next to `walkaway.sh`.)

Out-of-range or non-numeric values are ignored and the built-in default is used, so a
typo can't make it misbehave — and the file is **parsed, never executed**. The knobs:

| Knob | Default | Purpose |
|---|---|---|
| `LOCK_DELAY` | `30` | Seconds after the last door closes before locking. Range 5–600, but **keep ≤ ~90**: the real wait is ~1.3–1.8× this (each poll also does a `dumpsys`), and the screen only stays awake ~2–3 min after switch-off, so a bigger value can miss the lock entirely. |
| `DRY_RUN` | `1` | `1` = log `WOULD FIRE`, send no lock (safe). Set `0` to actually arm. |
| `ENABLED` | `1` | `0` = installed but inactive — stands down, never locks. |
| `DRIVER_DOOR_ONLY` | `1` | `1` = arm only on a driver-door exit; `0` = any door. |
| `POLL_ACTIVE` | `1` | Poll interval (s) after ignition off — 1 s catches a quick exit (1–10). |
| `POLL_DRIVE` | `5` | Poll interval (s) while driving / idle (1–30). |
| `POST_FIRE_CONFIRM` | `5` | Seconds to wait and recheck that the lock took (1–30). |
| `MAX_FIRES` | `3` | Lock attempts per stop before giving up (1–10; never hammers). |
| `MIN_ACC` | `3` | Only fire at this ACC state (off-standby). |
| `CHECK_ODEX` | `1` | `1` = refuse to run if the framework hash changed. |

### Turn it on/off

**From the NEMESIS Manager** (triple-press the Nav button) — if you installed the package:
- **Services → `autolock` → Start / Stop** — shows running/stopped state; a toggle with
  visible status. Stop disables it for the session; it starts again next boot.
- **Packages → Gen5 Auto-Lock → Launch** — flips a persistent pause flag that **survives
  reboots** (stays paused until you Launch again).

**From a shell** (either install mode), no restart needed:

```sh
touch /data/nemesis/gen5-autolock.off   # pause — stands down, won't lock
rm    /data/nemesis/gen5-autolock.off    # resume (re-arms on the next drive)
```

**Pause it before** you sit in the switched-off car with the key, hand it to a valet, or
drop it at service or a car wash — otherwise the fob gets left inside and it locks in. The
flag survives reboots. (`ENABLED=0` in the config disables it permanently.)

## Test (dry-run first)

With `DRY_RUN=1` (default), the daemon runs and logs but never locks. It writes to
`/data/nemesis/gen5-autolock.log`. Over a few real stops, confirm:

- it logs `WOULD FIRE` **only** after a genuine park → off → exit → doors closed;
- it **never** logs `WOULD FIRE` at boot, while you are getting in, or with a door open;
- **verify the liftgate reports open:** the daemon logs the raw door/trunk values on its
  `exit seen …` and `ARMED …` lines (e.g. `trunk=1`). Open the liftgate and confirm a
  `trunk=1` appears — either on those lines (liftgate already open as you get out) or as a
  `trunk/liftgate open — holding` line (liftgate opened *after* it armed; it should then
  resume when you close it). If `trunk` never leaves `0`, the field doesn't track the
  liftgate on your car (see [Limitations](#limitations)).

Only once that log looks right should you set `DRY_RUN=0`.

## Limitations

- **Key inside / no occupant detection** — see [Safety](#-safety--read-this-first).
- **Time-based, not proximity-based** — it can't tell you walked *away* vs. stepped out
  and stood next to the car.
- **Only active while the head unit is awake** after switch-off (a few minutes); if you
  sit longer than that and then leave, it won't lock (same as stock).
- **Trunk/liftgate is a safe assumption, not a verified one.** It won't lock while the
  liftgate reads open, and it holds (without needing a fresh exit) while you load cargo —
  but `mTrunkOpenedState` was never seen change during the original testing, so confirm
  it actually reports open on your car (see the liftgate check above) before trusting it.
- **The hood/frunk is not watched.** `mHoodStatus` isn't in `dumpsys`, so the car locks
  with the frunk open. Harmless to the lock itself (the hood isn't latched or trapped) —
  but a **fob left in the frunk** becomes a lockout when it shuts. Keep the fob on you.
- **Getting back in can lock you in.** Climbing back through the driver door after you'd
  gotten out reads as a fresh exit — it re-arms and locks with you inside after the delay.
  Pause it first (see [Turn it on/off](#turn-it-onoff)). The interior handle still opens a
  locked door from within.
- **Charging:** if you reach the charge port just as it locks, the port won't pop — you
  unlock, plug in, and it stays unlocked for the session (one lock per stop). Plug in
  first, or press LOCK after plugging in.

Full reasoning, the measured facts, and the detection analysis are in
[`docs/design.md`](docs/design.md) §8.

## License

[MIT](LICENSE).

## Disclaimer

Not affiliated with, endorsed by, or connected to Kia or Hyundai. This is an
independent modification for a rooted head unit. It controls vehicle locks and is
provided with no warranty of any kind. Rooting your head unit and automating vehicle
functions is entirely at your own risk and may affect your warranty. **You are
responsible for your vehicle and anything locked inside it.**
