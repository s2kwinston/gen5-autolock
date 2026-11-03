# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-02

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
- **Runtime on/off toggle** — `touch /data/nemesis/gen5-autolock.off` to pause (stands
  down, never locks) and delete it to resume; no restart needed. `ENABLED=0` does the
  same permanently.
- **Liftgate- and hood-aware arming** — won't lock while the liftgate or the hood/frunk is
  open, and *holds* (without demanding a fresh driver exit) while you load cargo or use
  the frunk, resuming when the lid closes. The liftgate comes from the body cache; the
  hood is **not** in `dumpsys`, so it's read TX-free from the system log line every stock
  BCM client prints on a door event (`mHoodSwitchState`). Both verified on the reference
  car. `HOOD_GUARD=0` turns the hood read off.
- **Real-seconds debounce** — `LOCK_DELAY` is counted from the monotonic `/proc/uptime`
  (with a poll-count fallback), so a slow poll can't stretch it and a clock sync after
  boot can't skip it. Measured on the reference car: the car stays lockable 178 s after
  the door closes; keep `LOCK_DELAY` ≤ ~120.
- **NEMESIS package** (`package/` + `tools/build-package.sh`, id `gen5.autolock`) — the normal
  install path. Registers the daemon as a service so NEMESIS starts it at **every boot**
  (no `/system` init hacking), and exposes an **on-screen toggle in the NEMESIS Manager**
  (Services → Start/Stop, or Packages → Launch). Install/uninstall lifecycle hooks seed a
  persistent config and clean up on removal.
- `docs/design.md` — full design: the measured facts, state machine, pre-checks, timing
  margins, the lock command, persistence, and limitations.
- **USB setting sticks** (`usb-sticks/`, built into per-stick zips by `tools/build-sticks.sh`) —
  change settings on the car with no PC-at-the-car and no shell; each is a `type=execute`
  one-shot, a settings update (not a reinstall), and persists:
  - `go-live/` and `test-mode/` — one-tap flip between LIVE and TEST MODE (`DRY_RUN`),
    editing only that line and keeping your other settings.
  - `custom-settings/` — edit a plain-text file to set any knob (e.g. `LOCK_DELAY`). It
    **merges** only the lines you set into the live config — your LIVE/TEST mode, other
    settings and comments stay — so changing the delay can never drop you back to test
    mode by accident. Refuses a file that sets nothing.
  - `get-log/` — read-only: copies the log, config and a body-control snapshot onto the
    USB (for non-shell users and the liftgate check); changes nothing on the car.
  - `ref-odex/` — for a firmware the gate doesn't know (or after a Kia update): pins the
    head unit's own framework files into `/data/nemesis/gen5-autolock-ref/` (verified
    byte-for-byte) and restarts the service, no shell needed. Re-running re-pins and says
    `REPLACED`.
- **Framework hash gate needs no setup on a verified build** — the daemon compares the
  md5 of the live `automotive*.odex` (toolbox `md5`) with the verified build(s) listed in
  the script (`KNOWN_MD5_*`); a match runs with zero user steps. Any other firmware still
  refuses to run (`FATAL: framework is not a verified build`) until the user pins their
  own odex (ref-odex stick) or sets `CHECK_ODEX=0`.
  Each ships a non-technical `README.txt`.
- **NEMESIS 1.16 Package Store descriptor** — `package/NEMESIS.data` is format `1.1`
  (`package-version`, `short-desc`, `detailed-desc`, `os="*.260507"`, `models`), so the
  package lists with the right compatibility colour; it keeps the 1.0 `types=` key so a
  NEMESIS 1.15 unit still registers the service. `tools/build-package.sh` now also emits
  `gen5-autolock-install.zip`, a ready USB install stick; all built zips land in `dist/`.
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

### Fixed (pre-release hardening)
- **USB mode sticks no longer depend on `printf`** (absent on this KitKat head unit): they
  rewrite the config with `echo` and refuse to install an empty result, so a GO LIVE /
  TEST MODE stick can't silently blank the config and still report success.
- **Config parsing tolerates inline `# comments` and trailing whitespace/CR** — e.g.
  `DRY_RUN=0   # go live` now takes effect instead of silently falling back to the default.
- **A cold-boot ACC read can't kill the daemon** — a low `mACCStatus` counts as power-down
  only after a live value has been seen, so a boot-time cache read of 0/1 no longer makes a
  `mode=background` service exit for the whole drive.
- **The framework reference odex survives package updates** — the hash-gate reference now
  lives at `/data/nemesis/gen5-autolock-ref/`, outside the package tree.
- **A package update no longer un-pauses the daemon** — `postuninstall` detects the update
  staging dir and leaves the pause flag alone.
- Corrected wording: re-entry is **not** occupant protection; the hood/frunk is absent from
  `dumpsys` but **is** observable via a TX-free listener (a possible future hood-hold).

### Known limitations
- **No key-inside protection.** The lock path has no interlock and the head unit
  receives no fob-presence signal (verified at the CAN layer); it will lock a key
  inside. Keep a spare outside the car.
- **No occupant detection**, time-based rather than proximity-based, and only active
  while the head unit is awake after switch-off.
- **Windows and sunroof are not watched** (no usable value on the head unit); it locks
  with them open, like stock. A fob shut in the frunk is still a lockout (the hood hold
  only applies while the hood is open).

[0.1.0]: https://github.com/s2kwinston/gen5-autolock/releases/tag/v0.1.0
