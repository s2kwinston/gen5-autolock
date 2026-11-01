# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-10-31

First public release — a working reference implementation. Pre-1.0: it ships in
dry-run and the key-inside limitation below is real, so treat it as "use with care,"
not battle-hardened.

### Added
- `walkaway.sh` — the walk-away auto-lock daemon: `BOOT → DRIVING → WAIT_EXIT → ARMED`
  state machine, fresh pre-check gate, one lock per stop with a bounded retry, and a
  framework odex hash gate.
- `DRY_RUN` mode (default on) — logs `WOULD FIRE` and sends no lock, for field-testing
  across real drives before arming.
- **External config file** (`gen5-autolock.conf`) — set `LOCK_DELAY` and every other knob
  without editing the daemon; survives updates. It is **parsed** for known `KEY=value`
  keys, never executed (a writable config can't run code as root). Values are
  range-clamped, so a bad entry falls back to the default. See `gen5-autolock.conf.example`.
- **Runtime on/off toggle** — `touch /data/local/tmp/gen5-autolock.off` to pause (stands
  down, never locks) and delete it to resume; no restart needed. `ENABLED=0` does the
  same permanently.
- **Trunk/liftgate-aware arming** — won't lock while the liftgate reads open, and *holds*
  (without demanding a fresh driver exit) while you load cargo, resuming when it closes.
- **NEMESIS package** (`package/` + `build-package.sh`, id `gen5.autolock`) — the normal
  install path. Registers the daemon as a service so NEMESIS starts it at **every boot**
  (no `/system` init hacking), and exposes an **on-screen toggle in the NEMESIS Manager**
  (Services → Start/Stop, or Packages → Launch). Install/uninstall lifecycle hooks seed a
  persistent config and clean up on removal.
- `docs/design.md` — full design: the measured facts, state machine, pre-checks, timing
  margins, the lock command, persistence, and limitations.
- `install/persistence.md` — boot-start via the NEMESIS package (plus manual fallbacks).
- `ref/` — where you place your own head unit's framework for the hash gate (proprietary
  binaries are never shipped here).

### Changed
- Pause-flag and log moved to **`/data/nemesis/`** (persists across reboots) from
  `/data/local/tmp/` (which NEMESIS wipes on every reboot). Config is read from
  `/data/nemesis/gen5-autolock.conf` when present, so it survives package updates.

### Security
- Config is **parsed, not sourced** — a config writable by another process cannot execute
  code in the root daemon. Install hooks `umask 077` and `chmod 600` the seeded config.
- Startup logs the effective config / pause-flag / log paths, so a stale or wrong pause
  path can't silently fail-open (you think it's paused while it keeps locking).

### Known limitations
- **No key-inside protection.** The lock path has no interlock and the head unit
  receives no fob-presence signal (verified at the CAN layer); it will lock a key
  inside. Keep a spare outside the car.
- **No occupant detection**, time-based rather than proximity-based, and only active
  while the head unit is awake after switch-off.
- **Liftgate unverified.** The trunk guard assumes `mTrunkOpenedState` tracks the rear
  liftgate; that field was never seen change during testing — verify it on your car.

[0.1.0]: https://github.com/s2kwinston/gen5-autolock/releases/tag/v0.1.0
