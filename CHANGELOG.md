# Changelog

All notable changes to this project are documented here. This project adheres to
[Semantic Versioning](https://semver.org/).

## [0.2.4] - 2026-11-17

### Changed
- **The passenger re-arm from 0.2.3 is now a setting, and it's off by default.** A front
  passenger door opening after you got out now blocks the auto-lock for that stop, like a
  rear door: it waits until the driver door opens and closes again. A passenger who got out
  after you might get back in and stay, and on the reference car someone left inside
  couldn't unlock with the inside button after an auto-lock. To get the 0.2.3 behavior back
  (it re-arms once every door is closed), add `PASSENGER_REARM=1` with the custom-settings
  stick. **If you're updating from 0.2.3, this changes back on its own.**
- The same rule now covers the wait before arming: a passenger door that newly opens while
  it's waiting (for example for the liftgate to close) cancels the exit too. A passenger
  door that was already open when you shut the driver door (getting out together) is fine.
- **It now tells you when it won't lock.** When a rear or passenger door cancels the
  auto-lock, the screen shows "door opened after you got out - won't auto-lock until the
  driver door opens and closes". Before, this was only in the log.

Bench: 131/131 (9 new: the default and opt-in passenger cases, a passenger door during the
liftgate wait, a passenger door open at the exit, a garbage setting value, the message, and
the key-sensor case). On-car confirmation pending.

## [0.2.3] - 2026-11-17

### Fixed
- **Your passenger getting out after you no longer stops the lock.** Before, any door
  reopening made it wait for the *driver* door to open and close again; a passenger
  getting out after you meant no lock that stop (seen on the reference car). Now, if only
  the front passenger door reopens, it re-arms as soon as every door is closed again and
  the countdown starts over. With the key sensor it keeps measuring from the driver's
  exit, so a passenger who lingers after the key has left doesn't make it hold.
- **A rear door opened after you get out always blocks the lock** until the driver door
  opens and closes again. Door data can't tell someone getting out of the back from a
  child or pet being put *in*, and a rear door with the child lock on can't be opened from
  inside. (0.2.2 still let one slip through if it opened while the daemon was waiting for
  another door to close.) A rear door already open when you shut the driver door, with
  everyone getting out together, is fine.
- **"key sensor ready" only appears when the board is actually connected.** It needs a
  board line from the last 3 s; before, a reading up to 10 s old counted, so unplugging the
  board just before starting the car could still show it.
- **The board's history keeps the end of a long drive.** `key_trace.log` now keeps the
  newest 1500–3000 lines of each start (the last hour or two) instead of the first 1500, so
  the stop is always in it.

### Changed
- **Safety docs corrected.** They said the interior handle always opens a locked door. On
  the reference car a passenger left in the front seat couldn't unlock with the inside
  unlock button after an auto-lock (it took the fob); the front interior handles open the
  door but trip the alarm, and a rear door with the child lock on can't be opened from
  inside at all. The README, FAQ and design notes now say so. The head unit doesn't receive
  the child-lock state (not in its body data or vehicle framework; not yet tested on-car).
- Code comments no longer imply the board is an Adafruit QT Py (the tested board is a
  Waveshare ESP32-S3 Mini flashed with the QT Py board setting). Behavior unchanged.

Bench: 122/122 (13 new: the passenger re-arm, three rear-door cases, a passenger-only exit
never arming, a door left open, the key-sensor passenger cases, the stale and fresh "ready"
message, and the history trim). On-car confirmation pending.

## [0.2.2] - 2026-11-16

The first public release of the optional **key sensor** (key-inside protection). 0.2.0
and 0.2.1 below were on-car test builds and were not published; their notes describe
what's included here. Without a sensor nothing changes: `KEY_GATE` stays off and the
plain installer behaves exactly as 0.1.1.

### Changed
- **`KEY_GONE_DEBOUNCE` default 45 → 20 s** (key sensor only). On the car, 45 s missed
  real locks: the head unit only stays awake about 3 minutes from when the driver door
  opens, and walking out of range plus 45 s of silence often didn't fit. Across four long
  drives and a 3-minute key-in-the-cupholder test, the longest the board went without
  hearing a key that was in the car was 7.5 s. At 20 s, the walk-away test locked 31 s
  after the door closed, and the key-inside test held for the full window.
- **Timing guidance corrected:** the lockable window is ~3 minutes from the driver door
  *opening*, not 178 s from it closing, so a door held open while unloading shrinks it,
  and a lock sent in its last seconds may not take. Keep `LOCK_DELAY` ≤ ~90 (was ≤ ~120).
- **Docs restructured.** The README is now a short front page; install and settings moved
  to `docs/install.md`, the FAQ and limitations to `docs/faq.md`, and the key sensor has
  its own guide, `docs/key-sensor.md` (parts, flashing the board, setup, first tests).
  `docs/design.md` gains §10 (the key gate) and the updated window measurements.
- The custom-settings stick no longer offers `HAZARD_LIVE`, and the example config marks
  it "leave 0": the hazard flash is untested on a car.
- The get-log stick's `README.txt` now lists every file it copies and warns that the head
  unit's own logs (`logcat.txt`, `dmesg.txt`) can contain personal details (phone name,
  Wi-Fi names, location, VIN); check them before sharing.

### Added
- **ESP32 firmware** (`esp32/key_scanner`) with build notes (`esp32/README.md`). You set
  your own tag's address (`TAG_ADDRESS`, upper or lower case); until it's set, the board
  reports nothing and the car fails safe. Tested board: Waveshare ESP32-S3 Mini
  (ESP32-S3FH4R2), built with the Arduino "Adafruit QT Py ESP32-S3 (4M Flash 2M PSRAM)"
  board setting; the Adafruit QT Py ESP32-S3 has the same chip but is untested on a car.
  (Corrected after release: the first version of these notes had the two boards swapped.)
  The scanning logic is what ran on the test car; the address handling is new for
  publishing and so far compile-checked only.

### Known issues
- After you get out, reopening a **different** door (passenger or rear) makes it wait for
  the driver door to open and close again; if that doesn't happen, it won't lock that stop.
- With the sensor, the board can hear keys faintly through a house wall when the car is
  parked right outside, and then holds the lock.
- The hazard flash would also fire while you stand next to the car (it can't yet tell
  that from a key left inside). It stays log-only (`HAZARD_LIVE=0`).
- The "key sensor ready" message accepts a reading up to 10 s old, so it can appear if the
  board is unplugged just before the car starts. The lock decision has the same limit.
- The board's history (`key_trace.log*`) keeps only the first hour after each start.

## [0.2.1] - 2026-11-13

### Fixed
- **The key reader could open a serial port that isn't the sensor.** This head unit
  already has `/dev/ttyACM0`/`ttyACM1` (and `ttyUSB0-2`) before any board is plugged
  in. 0.2.0 opened `/dev/ttyACM0` by default, so it could read and reconfigure one of
  those ports instead of the sensor. On the first on-car run it never saw the sensor;
  the daemon read the feed as offline and did not lock.
  The reader now opens only a `/dev/ttyACM*` whose USB device has the sensor's vendor id
  (`KEY_USB_VIDS`, default `239a 303a`), checked in sysfs before every open; every other
  node is skipped, never opened, and logged once with its vendor id and product name.
- Updating now stops the previous install's running key reader (only a process whose
  command line names `key-reader.sh`); restart the autolock service to start the new one.

### Added
- The get-log stick also saves key-sensor USB diagnostics: USB devices and their
  drivers, which device owns each serial node, which process holds each one open, plus
  `dmesg` and `logcat`.

## [0.2.0] - 2026-11-13

Optional key-inside protection: an ESP32 BLE key sensor on the head unit's USB port.
Off by default (`KEY_GATE=0`): with no sensor, nothing changes.

### Added
- **Key gate (`KEY_GATE=1`).** The lock fires only once the key tag on your key ring
  was heard at the exit and the sensor has then OBSERVED `KEY_GONE_DEBOUNCE` (45 s) of
  silence on one unbroken feed, i.e. the key LEFT. It never locks while the tag is
  heard, when the tag was never heard this boot, when it was already silent at the exit
  (dead tag battery, key not on you), across a sensor dropout or reconnect, or when the
  sensor is offline, stale or its data comes from a previous boot. The hold is
  non-terminal (a key that leaves later still locks) but ends `KEY_HOLD_MAX` (180 s)
  after the exit.
- `key-reader.sh`: reads the sensor's serial lines into `/data/nemesis/key_state`. The
  daemon starts it when `KEY_GATE=1` (single instance per boot). It logs first-light
  diagnostics (cdc_acm driver present, USB devices seen, connect/disconnect).
- On-screen messages via the head unit's own toast: one "key sensor ready" per boot, and
  a warning while you are still driving if the sensor is offline or the tag isn't heard.
- Key-left-inside hazard flash (lights only, `startFindingCar` mode 2 then stop). Dry-run
  until `HAZARD_LIVE=1`; never the panic alarm (mode 1).
- ESP32 firmware lives outside the head-unit package (`esp32/`, published in 0.2.2).
- `gen5-autolock-install-keysensor.zip`: the LIVE installer that also turns the key gate
  on in your existing config (an ordinary update never changes your settings).

### Changed
- Docs: NEMESIS Manager navigation updated for 1.16 (**My Packages** → Gen5 Auto-Lock →
  Launch; Launch shows `PAUSED` / `RESUMED` on screen). On NEMESIS 1.16.4+ a stopped
  service stays stopped until started again (on 1.15 it returned at the next boot).
  Verified on NEMESIS 1.16.4: the package and its running service survived the 1.15 →
  1.16.4 update untouched.

## [0.1.1] - 2026-11-02

Same day as 0.1.0, before any announcement: the installer now goes live by default.

### Changed
- **Two installers.** `gen5-autolock-install.zip` seeds `DRY_RUN=0` — **live from the
  first stop**, nothing else to do on a verified car. `gen5-autolock-install-testmode.zip`
  seeds `DRY_RUN=1` — runs and logs `WOULD FIRE`, never locks, for anyone who wants to
  watch the log first. The daemon's built-in default stays `DRY_RUN=1` (no config = never
  locks); an update never touches an existing config, so settings and mode survive.
- The install hook seeds the config from the package's `gen5-autolock.conf.seed` and
  prints the mode it ended up in. The bare package zip is no longer a release asset
  (it's inside the installers; `tools/build-package.sh` still produces it for the store).
- Docs rewritten around the one-stick path (README walkthrough, downloads table,
  package README, config template).

## [0.1.0] - 2026-11-02

First public release — a working, field-verified reference implementation. Pre-1.0:
the key-inside limitation below is real, so treat it as "use with care," not
battle-hardened.

### Added
- `walkaway.sh` — the walk-away auto-lock daemon: `BOOT → DRIVING → WAIT_EXIT → ARMED`
  state machine, fresh pre-check gate, one lock per stop with a bounded retry, and a
  framework odex hash gate.
- `DRY_RUN` test mode — logs `WOULD FIRE` and sends no lock. The daemon's built-in
  default; in 0.1.0 the installer also started in it (changed in 0.1.1).
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

[0.2.4]: https://github.com/s2kwinston/gen5-autolock/releases/tag/v0.2.4
[0.2.3]: https://github.com/s2kwinston/gen5-autolock/releases/tag/v0.2.3
[0.2.2]: https://github.com/s2kwinston/gen5-autolock/releases/tag/v0.2.2
[0.1.1]: https://github.com/s2kwinston/gen5-autolock/releases/tag/v0.1.1
[0.1.0]: https://github.com/s2kwinston/gen5-autolock/releases/tag/v0.1.0
