# Install, settings, and on/off

Everything about getting gen5-autolock onto the car and changing how it behaves. Read the
[Safety section of the README](../README.md#safety) first. Using the optional key sensor?
Its setup (parts, flashing the board, first tests) is in [key-sensor.md](key-sensor.md).

- [Which zip do I need?](#which-zip-do-i-need)
- [Set it up (plain-language walkthrough)](#set-it-up)
- [Install details](#install-details)
- [Settings](#settings)
- [Turn it on / off](#turn-it-on--off)
- [Optional: test mode first](#optional-test-mode-first)

## Which zip do I need?

Everything on the [Releases](https://github.com/s2kwinston/gen5-autolock/releases) page
is a USB stick in a zip. The routine is always the same: **extract the zip to the root of
an empty USB stick** (FAT32 or exFAT), start the car, wait for the screen to load, insert
the stick, tap **Yes**, remove it. You never need more than one at a time.

**Install — pick one:**

| Zip | What it is |
|---|---|
| `gen5-autolock-install.zip` | **Without a key sensor.** Installs the daemon as a NEMESIS package; it starts by itself every time the car starts and is **LIVE from your next stop**, locking `LOCK_DELAY` (30) seconds after you shut the door. |
| `gen5-autolock-install-keysensor.zip` | **With the key sensor** (an ESP32 board on the USB port + a tag on your keys). Same package, LIVE, with the key gate switched on: it locks only after your key has left. See [key-sensor.md](key-sensor.md). |
| `gen5-autolock-install-testmode.zip` | The plain installer, but it starts in **TEST MODE**: runs and logs `WOULD FIRE`, never locks, until you insert the GO LIVE stick. |

Re-inserting an installer (same or newer version) updates the package; your settings and
LIVE/TEST mode are kept. The key-sensor installer additionally switches the key gate on.

**Settings and tools — only when you need them:**

| Zip | What it does | When you need it |
|---|---|---|
| `gen5-autolock-go-live.zip` | Switches to **LIVE**: it really locks the car. | After the test-mode installer, once the log looks right. |
| `gen5-autolock-test-mode.zip` | Switches back to **TEST MODE**: runs and logs, never locks. | Any time you want it to stop locking without uninstalling. |
| `gen5-autolock-custom-settings.zip` | Changes a setting, e.g. the lock delay. Edit its text file on your computer first; **only the lines you set change**. | When a default isn't what you want. |
| `gen5-autolock-get-log.zip` | **Read-only.** Copies the log, settings and diagnostics onto the stick, including the head unit's own system and kernel logs (`logcat.txt`, `dmesg.txt`). Changes nothing. Those two can contain personal details (phone name, Wi-Fi names, location, VIN): check them before you share the folder. | When you want to see what it did, or something looks off. |
| `gen5-autolock-ref-odex.zip` | Accepts a car software version the daemon doesn't recognise (another model/firmware, or after a Kia update). | **Only** if the log says `FATAL: framework is not a verified build`. Not needed on a 2022 US EV6. |

(The bare NEMESIS package, `gen5.autolock.zip`, is what's *inside* the installer zips; it's
built by `tools/build-package.sh` for `nemesis install` from a shell and for the Package
Store, and isn't a USB stick by itself.)

## Set it up

**Once:**
1. Get the installer zip you picked from the Releases page and extract it to the **root**
   of a USB stick.
2. Start the car, wait for the screen to fully load, insert the stick, tap **Yes**. The
   screen says *NEMESIS operation completed successfully*.
3. That's it: installed, **starts by itself every time you start the car**, and **live
   from your next stop**. On a verified car (2022 US EV6, firmware 260507) there is nothing
   else to do. On any other firmware it refuses to run until you consciously accept that
   firmware with the **ref-odex** stick (see [Install details](#install-details)).
   With the key sensor, continue with [key-sensor.md, step 5](key-sensor.md#5-install-in-the-car).

**Every drive (automatic, no USB):** park, switch off, get out, close the door. It locks
by itself about `LOCK_DELAY` seconds later (30 by default), or with the key sensor, about
20 s after your key is out of range.

**Change a setting:** use the **custom-settings** stick: edit `LOCK_DELAY=30` (etc.) in its
text file and insert it. That's a settings update, *not* a reinstall; the setting sticks
and the service restarts by itself. Full steps are on the stick's `README.txt`.

## Install details

**Prerequisites:** NEMESIS root on a head unit matching
[Compatibility](../README.md#compatibility). A toolbox shell (KitKat `sh`); no
`grep`/`awk`/`busybox` needed.

**As a NEMESIS package (the normal way).** NEMESIS **starts the daemon at every boot** (its
own service manager, no `/system` init hacking) and gives you an **on-screen toggle in
the NEMESIS Manager**. Build the installers yourself with:

```sh
tools/build-package.sh    # -> dist/gen5-autolock-install.zip (LIVE), -install-testmode.zip,
                          #    -install-keysensor.zip, gen5.autolock.zip
tools/build-sticks.sh     # -> the settings / get-log / ref-odex sticks in dist/
```

An installer is the package zip plus a `type=install` `NEMESIS.data` (full steps and the
file contents in [`package/README.md`](../package/README.md)). It installs to
`/data/nemesis/apps/gen5.autolock/`, seeds your config at
`/data/nemesis/gen5-autolock.conf`, and starts the service: **live** (the standard and
key-sensor installers seed `DRY_RUN=0`; the test-mode installer seeds `DRY_RUN=1`, log
only). An update never resets an existing config.

**Framework hash gate.** The daemon refuses to run unless the vehicle framework is one the
lock transaction was verified against (an OTA can move transaction codes and turn a "lock"
into something else). It compares the md5 of the live `automotive*.odex` with the verified
build(s) listed in the script; on a 2022 US EV6 on firmware 260507 that passes with no
setup. On any other firmware it logs `FATAL: framework is not a verified build` and exits
(fail-safe) until you consciously accept that firmware: insert the **ref-odex** stick
([`usb-sticks/ref-odex/`](../usb-sticks/ref-odex/)), which pins your head unit's own odex
into `/data/nemesis/gen5-autolock-ref/` (proprietary files, never shipped here) and
restarts the service, or set `CHECK_ODEX=0`. See [`ref/README.md`](../ref/README.md).

**Standalone (advanced).** You can run `walkaway.sh` directly without the package; then
you arrange your own boot launch (something must start it on every head-unit boot, before
you switch the car off). The daemon also reads a `gen5-autolock.conf` next to
`walkaway.sh`. The package is the supported path.

## Settings

**You never edit the script.** Settings live in `/data/nemesis/gen5-autolock.conf`,
changed on the car (no PC, no shell) with a USB stick from
[`usb-sticks/`](../usb-sticks/): insert, tap Yes, done.

| Stick | What it does |
|---|---|
| `usb-sticks/go-live/` | Switch to LIVE (really locks). Keeps your other settings. |
| `usb-sticks/test-mode/` | Switch to TEST MODE (runs, logs, never locks). Keeps your other settings. |
| `usb-sticks/custom-settings/` | Edit the plain-text file (e.g. `LOCK_DELAY=15`) and insert: changes **only** the lines you set. |
| `usb-sticks/ref-odex/` | One-time on other firmware: pins your head unit's own framework for the hash gate. |
| `usb-sticks/get-log/` | Read-only: copies the log, settings, a body-control snapshot and key-sensor diagnostics onto the stick (its `README.txt` lists every file, and which ones to check before sharing). |

Out-of-range or non-numeric values are ignored and the built-in default is used, so a typo
can't make it misbehave, and the file is **parsed, never executed**.

| Setting | Default | Purpose |
|---|---|---|
| `LOCK_DELAY` | `30` | Seconds after the last door closes before locking (real seconds). Range 5–600, but **keep it short (≤ ~90)**: the head unit only stays awake ~3 minutes from when you open the driver door to get out, and a door held open while you unload uses that time up. |
| `DRY_RUN` | `1` built-in; the installers seed `0` (test-mode: `1`) | `1` = log `WOULD FIRE`, send no lock. `0` = really lock. |
| `ENABLED` | `1` | `0` = installed but inactive: stands down, never locks. |
| `DRIVER_DOOR_ONLY` | `1` | `1` = arm only on a driver-door exit; `0` = any door. |
| `HOOD_GUARD` | `1` | `1` = hold while the hood/frunk is open (read TX-free from the system log). |
| `POLL_ACTIVE` | `1` | Poll interval (s) after ignition off (1–10). |
| `POLL_DRIVE` | `5` | Poll interval (s) while driving / idle (1–30). |
| `POST_FIRE_CONFIRM` | `5` | Seconds to wait and recheck that the lock took (1–30). |
| `MAX_FIRES` | `3` | Lock attempts per stop before giving up (1–10). |
| `MIN_ACC` | `3` | Only fire at this ACC state (off-standby). |
| `CHECK_ODEX` | `1` | `1` = refuse to run if the framework hash isn't verified or pinned. |
| **Key sensor** | | Only matter with the key sensor; see [key-sensor.md](key-sensor.md). |
| `KEY_GATE` | `0` (the key-sensor installer sets `1`) | `1` = lock only after the key tag was heard at the exit and then went quiet. |
| `KEY_GONE_DEBOUNCE` | `20` | Seconds of observed silence that mean "the key left" (10–600). Don't raise it much: the head unit can fall asleep first. |
| `KEY_HOLD_MAX` | `180` | Seconds after the exit to keep waiting for the key to leave (60–1800). |
| `KEY_STALE` | `10` | Seconds without a sensor line before the sensor counts as offline (3–120). |
| `KEY_BOOT_GRACE` | `60` | Seconds after start before an offline / tag-not-heard warning (10–600). |
| `KEY_READY_TOAST` | `1` | `0` = no "key sensor ready" message. |
| `FLASH_DELAY`, `HAZARD_LIVE`, `HAZARD_SECS` | `60`, `0`, `3` | The "key left inside" hazard flash. **Leave `HAZARD_LIVE=0`**: untested on a car. |

## Turn it on / off

**From the NEMESIS Manager** (three quick presses of the **Nav** button):
- **My Packages → Gen5 Auto-Lock → Launch** flips a persistent pause flag that **survives
  reboots** (stays paused until you Launch again). On NEMESIS 1.16+ the screen shows
  `PAUSED` / `RESUMED`.
- **Services → `autolock` → Start / Stop** shows the running state. On NEMESIS 1.16.4+ a
  stopped service **stays stopped** until you press Start (on 1.15 it came back at the
  next boot).

**From a shell**, no restart needed:

```sh
touch /data/nemesis/gen5-autolock.off   # pause: stands down, won't lock
rm    /data/nemesis/gen5-autolock.off    # resume (re-arms on the next drive)
```

**Pause it before** you sit in the switched-off car with the key, hand it to a valet, or
drop it at service or a car wash. Or use the TEST MODE stick (logs only), or `ENABLED=0`
to disable it for good.

## Optional: test mode first

With the test-mode installer (or the TEST MODE stick), the daemon runs and logs but never
locks. It writes to `/data/nemesis/gen5-autolock.log` (no shell? the **get-log** stick
copies it onto the USB). Over a few real stops, confirm:

- it logs `WOULD FIRE` **only** after a genuine park → off → exit → doors closed;
- it **never** logs `WOULD FIRE` at boot, while you are getting in, or with a door open;
- **liftgate and hood:** the `exit seen …` and `ARMED …` lines show `trunk=1` / `hood=1`
  when they're open. Both are verified on the reference car; on any other car, open each
  and confirm the value appears, either on those lines or as a `… open — holding` line
  (then it should resume when you close it). If one never leaves `0`, that guard is blind
  on your firmware.

Once that log looks right, the **GO LIVE** stick switches it to locking.
