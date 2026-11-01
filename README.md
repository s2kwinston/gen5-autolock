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

1. **Prerequisites:** NEMESIS root on a head unit matching
   [Compatibility](#compatibility). A toolbox shell (KitKat `sh`) — no
   `grep`/`awk`/`busybox` needed.

2. **Framework hash gate (recommended).** The daemon refuses to run if the vehicle
   framework no longer matches what the lock transaction was verified against (an OTA
   can move transaction codes and turn a "lock" into something else). Copy your head
   unit's own framework into `ref/`:

   ```sh
   cp /system/framework/automotive.odex          /path/to/ref/
   cp /system/framework/automotive-service.odex   /path/to/ref/
   ```

   These are proprietary and stay on your device — they are **not** shipped with this
   repo. To skip the gate (not recommended), set `CHECK_ODEX=0` at the top of the
   script. See [`ref/README.md`](ref/README.md).

3. **Persistence.** The daemon must be running before you switch off, so it has to
   start at each head-unit boot. That is a device-specific `/system`/init change and is
   **not** bundled — see [`install/persistence.md`](install/persistence.md) for the
   options and trade-offs.

## Configure

**You don't need to edit the script.** Copy the example config next to `walkaway.sh`
and change what you want — it survives script updates:

```sh
cp gen5-autolock.conf.example gen5-autolock.conf
# edit gen5-autolock.conf, e.g. LOCK_DELAY=45
```

Out-of-range or non-numeric values are ignored and the built-in default is used, so a
typo can't make it misbehave. The knobs:

| Knob | Default | Purpose |
|---|---|---|
| `LOCK_DELAY` | `30` | Seconds after the last door closes before locking (5–600). |
| `DRY_RUN` | `1` | `1` = log `WOULD FIRE`, send no lock (safe). Set `0` to actually arm. |
| `ENABLED` | `1` | `0` = installed but inactive — stands down, never locks. |
| `DRIVER_DOOR_ONLY` | `1` | `1` = arm only on a driver-door exit; `0` = any door. |
| `POLL_ACTIVE` | `1` | Poll interval (s) after ignition off — 1 s catches a quick exit (1–10). |
| `POLL_DRIVE` | `5` | Poll interval (s) while driving / idle (1–30). |
| `POST_FIRE_CONFIRM` | `5` | Seconds to wait and recheck that the lock took (1–30). |
| `MAX_FIRES` | `3` | Lock attempts per stop before giving up (1–10; never hammers). |
| `MIN_ACC` | `3` | Only fire at this ACC state (off-standby). |
| `CHECK_ODEX` | `1` | `1` = refuse to run if the framework hash changed. |

### Turn it on/off without stopping it

Toggle at runtime, no restart needed:

```sh
touch /data/local/tmp/gen5-autolock.off   # pause — stands down, won't lock
rm    /data/local/tmp/gen5-autolock.off    # resume (re-arms on the next drive)
```

Handy when you're about to sit in the car with the key, or lending it to someone. The
off-file survives reboots, so it stays paused until you remove it. (`ENABLED=0` in the
config does the same thing permanently.)

## Test (dry-run first)

With `DRY_RUN=1` (default), start the daemon and drive normally. It writes to
`/data/local/tmp/gen5-autolock.log`. Over a few real stops, confirm:

- it logs `WOULD FIRE` **only** after a genuine park → off → exit → doors closed;
- it **never** logs `WOULD FIRE` at boot, while you are getting in, or with a door open;
- **verify the liftgate:** open it and check the log says `trunk/liftgate open — holding`
  (and that it resumes when you close it). This confirms the car actually reports the
  liftgate to the head unit — it was never exercised during the original testing (see
  [Limitations](#limitations)).

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
