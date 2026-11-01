# Walk-Away Auto-Lock — Design

**Vehicle:** 2022 US Kia EV6 GT-Line, Gen5W AVNT head unit, firmware
`CV_E.USA.S5W_M.V015.012.260507` (Android 4.4.2 / SDK 19, `tcc803x`).
**Platform:** [NEMESIS](https://github.com/xwtk/hmg_nemesis) root on the head unit,
`isSupportMMCAN = 1` (MMCAN lock path).
**Status:** Reference implementation. Ships in dry-run; see the safety notes below and
in the [README](../README.md).

---

## 0. Read first — the safety boundary

1. **Key-inside: no protection (tested).** In a controlled hands-off test the car
   **locked and stayed locked for 90 s with a key inside** — the alarm armed on the
   same timeline as the no-key control. So `lockDoor(true)` on this **relay** path
   (`bcm 5`) is neither refused nor auto-reverted: an auto-lock **can lock a fob inside
   the car.** The alternative telematics lock (`tmu 4`) was tested separately and is
   **inert** on this car (no effect with or without a key — no active remote-services
   session to carry it), so it is not a safer substitute. No software guard is
   possible: the head unit receives **no fob-presence signal at all**, confirmed at the
   CAN-protocol layer (§8). Deploying is a **risk-acceptance decision**, not a safety
   guarantee. In normal use — you walk away *with* the key — the feature is unaffected.
2. **Persistence is handled by the package.** Running every drive means something must
   start the daemon at each boot; the NEMESIS package registers it as a service that
   NEMESIS starts at boot — **no `/system`/init change of your own** (see §7 and
   [`install/persistence.md`](../install/persistence.md)).

---

## 1. What it does

Replicate the OEM "walk-away lock" the US body module does not support (its setting
reports unsupported). Plain-language behavior: **after you park, turn the car off, get
out, and close the door, the car locks itself a short time later — once.** It never
unlocks, never fights a lock you perform yourself, and stands down for the rest of that
stop.

This matters because of a measured quirk: **the car auto-unlocks when you turn it off**
("Auto Unlock at Vehicle Off" on).

---

## 2. Facts the design is built on

All grounded in on-car measurement and the decompiled stock framework.

| # | Fact |
|---|---|
| F1 | Turning the car off auto-unlocks the doors (`mLockState` 0→1 the moment `mIgnition1`→false). |
| F2 | The exit is visible: the driver door goes open→closed in the body-control cache. |
| F3 | After ignition off, `mACCStatus` steps 5 → 4 (transitioning, ~6–18 s) → 3 (off-standby) → 1 → 0 (dead). The cache is live and correct throughout `acc==3`. |
| F4 | The head unit survives to roughly 187–200 s after ignition off on runs that locked early. Shutdown tracks the *lock* event more tightly than ignition-off, so an **unlocked** unit likely stays awake somewhat longer (not directly measured). |
| F5 | `lockDoor(true)` = `service call com.hkmc.micom.bcm 5 i32 1`. In `IBCMService$Stub` the `onTransact` case `0x5` does `enforceInterface` → `readInt()` → non-zero ⇒ `lockDoor(true)`. No permission/ACL check, no software safety check. |
| F6 | The MMCAN lock is a clean momentary pulse that self-releases: `C_PreCrankReq=1` now → (+1000 ms) relay `C_CtrlDrLockRlyIBOX=1` → (+500 ms) relay=0. Identical to the OEM / remote-services lock. No stuck relay. |
| F7 | `dumpsys com.hkmc.micom.bcm` prints the live cache with labels and sends **no** CAN. Door/lock/ignition/acc are all readable from it. |
| F8 | `mHoodStatus` and `mGearPpositionClutch` exist as fields but are **not printed** by `dumpsys` (`BcmStatus.toString()` omits them), so they are invisible to a `dumpsys`/shell reader like this daemon. The hood is *not* fundamentally unobservable, though: it arrives passively over CAN (`RES_HOODSW_STATE`) and is pushed to every registered `IBCMListener` as the 10th arg of `onDoorAllStateChanged` — a small, TX-free `app_process` listener client could read it (basis for a possible future hood-guard). The only *hood-named Binder getter*, `getHoodStatusInfo()`, is void and does trigger a CAN TX, which is why a `service call` read is avoided — but that is a safe-reads policy choice, not a hard limit. |

**State encodings (confirmed across all runs):**

| Field | Values |
|---|---|
| `mLockState` | 0 = Locked, 1 = Unlocked |
| `mDrvOpenedState` / `mPas` / `mRL` / `mRR` / `mTrunkOpenedState` | 0 = Closed, 1 = Open |
| `mIgnition1` / `mIgnition2` | `true` / `false` |
| `mACCStatus` | 0 = off, 1 = shutting down, 3 = off-standby, 4 = transitioning, 5 = ignition on |
| `mStole` (alarm) | 1 = unset (ignition on), 2 = armed (locked) |

---

## 3. State machine

```
                    start state = BOOT (stands down until the first ignition-on)
                    ignition on (mIgnition1=true)  →  reset to DRIVING from ANY state
                    acc <= 1 (head unit dying)     →  DEAD from ANY state

  (BOOT) ──first ignition-on──┐
                              ▼
  ┌──────────┐  IGN off        ┌────────────┐
  │ DRIVING  │ ──────────────► │ WAIT_EXIT  │
  │ (IGN on) │                 │ (watch for │
  └──────────┘                 │  the exit) │
       ▲                       └─────┬──────┘
       │ IGN on (reset)              │ driver door open→close
       │                             │ AND all doors closed
       │                             │ AND acc==3 AND lock==1
       │                             ▼
       │                       ┌────────────┐  any door/trunk opens
       │                       │  ARMED     │ ──────────────────────► back to WAIT_EXIT
       │                       │ (debounce  │                         (needs a fresh exit)
       │                       │  counting) │
       │                       └─────┬──────┘
       │                             │ lock→0 (you locked it) ─────►  DONE
       │                             │ acc<3 (dying) ──────────────►  DEAD
       │                             │ debounce >= LOCK_DELAY
       │                             │ AND final fresh pre-check OK
       │                             ▼
       │                        ┌─────────┐  locked within POST_FIRE_CONFIRM?
       │                        │  FIRE   │   (DRY_RUN=1: log only → DONE)
       │                        │ lockDoor│──── yes ───►  DONE (success)
       │                        └────┬────┘
       │                             │ no
       │              fires<MAX ──────┤───── fires>=MAX ─────►  GAVE_UP (log loudly)
       │              back to WAIT_EXIT (needs a FRESH exit — no timer re-arm)
       │                             │
       └─────────────────────────────┘
```

- **BOOT** — the daemon just started (normally at head-unit boot) and has **not seen a
  drive yet**. While ignition is off it stands down and does nothing. This stops a
  boot-on-approach (the unit wakes as you walk up, engine still off) from being read as
  a park-and-exit and locking you in as you climb in. The first ignition-on promotes
  BOOT → DRIVING.
- **DRIVING** — ignition on. The reset point. Clears the exit flag, the fire count, and
  the debounce. On ignition off → WAIT_EXIT.
- **WAIT_EXIT** — ignition off, waiting to see the driver leave. Arms only after the
  **driver door** goes open→closed *and* all doors are closed *and* `acc==3` *and*
  `lock==1`. The driver-door requirement (not "any door") avoids false arming from a
  passenger-only movement.
- **ARMED** — debounce counting. `lock→0` → DONE (you or the car locked it; never
  double-send). `acc<3` → DEAD. A reopen is handled by *what* reopened:
  - a **door** reopens → WAIT_EXIT, a fresh **driver**-door open→close is required before
    it can arm again. NOTE: this is *not* occupant protection — the daemon cannot tell a
    real exit from someone climbing back IN, so a re-entry through the driver door reads as
    a fresh exit and it will arm (and lock) with them inside after the debounce. Pause it
    before sitting in a switched-off car (the interior handle always opens a locked door);
  - the **trunk/liftgate** reopens while the doors stay closed (cargo access, not
    re-entry) → **hold**: it won't lock while the liftgate is open and the debounce
    pauses, but the exit still counts, so it resumes the moment the liftgate closes — no
    second trip in and out of the driver's seat required.
- **FIRE** — send `lockDoor(true)` once; confirm `mLockState→0` within
  `POST_FIRE_CONFIRM` s. If it locked → DONE. If not → back to **WAIT_EXIT** (keep the
  fire count). The daemon retries only after a *genuinely new* driver exit, never on a
  timer — a timer re-arm would re-fire at a driver who just climbed back in and closed
  their own door. If a key really was left inside and the driver has gone, no new exit
  occurs and the daemon simply never fires again.
- **DONE** — stood down for this stop. Only a new ignition-on resets to DRIVING.
- **GAVE_UP** — reached `MAX_FIRES` without locking. Terminal, logged loudly. The cause
  is unknown; note this lock path has **no** key-inside interlock, so a refusal is *not*
  evidence of a key inside. Either way, leaving the car unlocked is the safe outcome —
  not hammering the relay.
- **DEAD** — `acc<=1`; the head unit is powering down. Exit the loop cleanly.

---

## 4. Pre-checks (the gate before FIRE)

Read a **fresh** `dumpsys com.hkmc.micom.bcm` immediately before firing. ALL must hold:

| Condition | Required | Why |
|---|---|---|
| `mIgnition1` | `false` | Not driving / not keyed on |
| `mIgnition2` | `false` | Belt-and-suspenders on ignition |
| `mACCStatus` | `3` | Stable off-standby — not 4 (still settling), not ≤1 (unit dying) |
| `mLockState` | `1` | Currently unlocked; if already 0 there is nothing to do |
| `mDrvOpenedState` | `0` | Driver door closed |
| `mPasOpenedState` | `0` | Passenger door closed |
| `mRLOpenedState` | `0` | Rear-left closed |
| `mRROpenedState` | `0` | Rear-right closed |
| `mTrunkOpenedState` | `0` | Trunk closed |
| *exit seen* | driver door open→close observed this cycle | Proves the driver got out |
| *debounce* | ≥ `LOCK_DELAY` s continuously true, no reopen | Walk-away, not "sat down and switched off" |
| *fires* | `< MAX_FIRES` | One-shot per cycle, plus bounded retries |

**Deliberately not gated (not in the `dumpsys` output — F8):** the **hood/frunk**
(`mHoodStatus` isn't in the dump, so this `dumpsys`-based daemon can't see it; locking the
doors with the hood ajar is harmless — the hood isn't latched or trapped. It *could* be
watched via a TX-free listener client (F8), so a hood-hold is a feasible future addition)
and **gear in P** (`mGearPpositionClutch` not in the dump; ignition-off forces P on an EV,
and we only fire at `acc==3`).

---

## 5. Timing

| Knob | Default | Rationale |
|---|---|---|
| `POLL_DRIVE` | 5 s | Poll interval while ignition is on / idle. Nothing time-critical. |
| `POLL_ACTIVE` | 1 s | Poll interval after ignition off. 1 s (not 3 s) because a quick exit — a driver door open for only a few seconds — can fall between slower polls and never arm. One `dumpsys` is well under a second. |
| `LOCK_DELAY` | 30 s | Debounce after the last door closes. Long enough that reopening to grab something doesn't lock you out; short enough to stay well inside the power window. |
| `POST_FIRE_CONFIRM` | 5 s | Wait-and-recheck for `mLockState→0`. The MMCAN pulse completes in ~1.5 s (F6), so 5 s is comfortable. |
| `MAX_FIRES` | 3 | Cap on lock attempts per stop. Prevents hammering a module that is not locking. |

**Margin:** typical fire time ≈ ignition-off + exit (~20 s) + `LOCK_DELAY` (30 s) ≈
50–65 s. The earliest observed head-unit death was ~187 s after ignition-off (and that
is the pessimistic, locked-early reading), leaving ≥ ~2 min of margin. After the daemon
locks, the unit shuts down ~170 s later — expected and fine; the job is done. A much
longer window (e.g. `LOCK_DELAY` > 2 min) would need either a dedicated unlocked-hold
measurement or `requestPwrKeepStart` (power service transaction 22) — out of scope.

---

## 6. The lock command

```sh
service call com.hkmc.micom.bcm 5 i32 1   # lockDoor(true)
```

- Verified transaction and argument (F5): `i32 1` → non-zero → `lockDoor(true)` = LOCK.
  **Never `i32 0`** (that is unlock — the daemon has no unlock path by invariant).
- Full MMCAN effect (F6): `C_PreCrankReq=1` immediately, then after ~1 s the lock relay
  pulses on for 500 ms and releases. Momentary, self-clearing, identical to the OEM lock
  button and remote-services lock.
- `com.hkmc.micom.bcm` is the registered service name; `service call` writes the
  interface token automatically. Proven live on the target.

---

## 7. Persistence

The daemon must be running before ignition-off each drive, so it has to start at each
boot. The supported way is to install it as a **NEMESIS package** that registers the
daemon as a service (`mode=background`): NEMESIS's watchdog starts the service manager
at boot, which starts the service — no `/system` init change of your own. `background`
(start once per boot, no auto-restart) matches the daemon exiting cleanly at power-down.
The Manager's Services screen then doubles as the enable/disable control. See
[`../package/README.md`](../package/README.md) and
[`install/persistence.md`](../install/persistence.md). It is a lightweight polling shell
script — no `app_process`/Java is required.

---

## 8. Known limitations

- **No fob-proximity signal.** This is time-based (debounce), not distance-based like
  the OEM feature. It cannot know the driver actually walked *away* vs. stepped out and
  stood by the car.
- **Key left inside = confirmed lockout risk.** This lock path has no anti-lockout: the
  car locks and stays locked with a key inside (§0). The mechanical blade lives in the
  fob, so recovery needs a **spare kept outside the car**. In normal use the driver
  carries the fob, so the exposure is specifically "set the fob down inside, close up,
  walk away."
- **Why a key-inside guard is impossible here (not merely hard).** The head unit is
  wired to the lock *actuator* and to fob *status* bytes — never to the fob *ranging*
  sensor. The complete body→head-unit CAN interface list (`BODY$Bcan$TE_RX_IL`) carries,
  for anything key-related, only: fob battery warning (`C_FOBBatteryStatusInfo`),
  smart-key remote-start status (`C_SMKTele*`), digital-key provisioning metadata
  (`DigitalKeyInfo*`), and a generic cluster warning-message channel (`CDM_WarnMsg`).
  There is **no** fob-presence or fob-location signal, and the string "key in vehicle"
  appears nowhere in the framework — that telltale is rendered by the instrument-cluster
  ECU from data the smart-key module keeps to itself. Approach-unlock works because the
  smart-key module actuates the locks and we see the *result* (doors unlock); we never
  see the fob-ranging *input*. Reading fob-inside would require tapping the smart-key ↔
  cluster CAN directly with external hardware — out of scope for a head-unit daemon.
- **Occupant left inside.** The daemon can lock with a person inside (occupancy is not
  detectable). The interior handle always opens the door from inside, so this is not
  entrapment, but it is startling, and opening a door after lock trips the armed alarm.
- **Head-unit death window.** If the driver sits longer than the unit survives after
  ignition-off and then exits, the daemon is already gone and the car stays unlocked
  (same as stock — no worse). Lock manually in that case.
- **Driver exits via a non-driver door** (rare) — won't arm under the driver-door-only
  trigger. Configurable via `DRIVER_DOOR_ONLY=0` at the cost of more false arming.
- **Trunk/liftgate guard is assumed, not verified.** The daemon treats
  `mTrunkOpenedState` as the rear liftgate: `all_closed` requires it to be `0`, so it
  won't lock while the liftgate reads open, and it holds (see §3) while you load cargo.
  **But the liftgate was never opened during testing** — every captured dump had
  `mTrunkOpenedState: 0` — so there is no on-car confirmation this field actually tracks
  the liftgate. If it doesn't, the guard is blind. Verify it (open the liftgate, check
  the field flips to 1, or watch the log for `trunk/liftgate open — holding`) before
  relying on it. The **frunk** (front trunk) maps to `mHoodStatus`, which this daemon does
  not read (it isn't in `dumpsys` — F8), so a frunk left open is invisible to it and the
  car still locks. That is harmless for the lock itself (the hood isn't latched or
  trapped); the one real hazard is a **fob left in the frunk**, which becomes a lockout
  when the hood shuts (the frunk has no outside/app release) — keep the fob on you. The
  hood *could* be watched via a TX-free listener (F8); a hood-hold is a possible future
  addition.

---

## 9. Config & control

### Config file
Rather than editing the script, use a `gen5-autolock.conf` (one `KEY=value` per line,
**parsed** for known keys at startup — never executed, so a writable config can't run
code as root) to override any knob. The daemon reads, in order: `$GEN5_CONF`, then
`/data/nemesis/gen5-autolock.conf` (persistent, survives package updates — the package
seeds it there), then one beside the script. Every value is **range-clamped** after
loading, so an out-of-range or non-numeric entry falls back to the default rather than
misbehaving.

### Runtime on/off
Three ways, in order of convenience once the package is installed:
- **Manager → Services → `autolock` → Start/Stop** — shows state; disables for the session.
- **Manager → Packages → Launch** — runs `toggle.sh`, flipping the pause flag.
- **Shell:** `touch /data/nemesis/gen5-autolock.off` pauses (stands down, checked every
  poll — no restart); delete it to resume. The flag lives under `/data/nemesis` so it
  **persists across reboots** (NOT `/data/local/tmp`, which NEMESIS wipes on reboot).
`ENABLED=0` in the config is a permanent disable.

### Knobs

All knobs live at the top of [`walkaway.sh`](../walkaway.sh) (override in the config):

```
POLL_DRIVE=5      POLL_ACTIVE=1       LOCK_DELAY=30    POST_FIRE_CONFIRM=5
MAX_FIRES=3       DRIVER_DOOR_ONLY=1  MIN_ACC=3        DRY_RUN=1
ENABLED=1         CHECK_ODEX=1
```

`DRY_RUN=1` (the default) logs `WOULD FIRE` and sends **no** lock. Leave it on and watch
`/data/nemesis/gen5-autolock.log` across several real drives — confirm it would fire only
on a genuine park-and-exit, and never at boot or while getting in — then set it to `0` to
actually arm.
