# EV6 Walk-Away Auto-Lock

Locks a Kia EV6 after you park, switch off, get out and walk away: the "walk-away lock"
the US body module doesn't offer. A small shell daemon on the head unit under
[NEMESIS](https://github.com/xwtk/hmg_nemesis) root, talking to the body-control module
through the stock vehicle service. Optional add-on: a **key sensor** so it never locks
with the key inside.

> [!CAUTION]
> **THIS LOCKS A REAL CAR.** On its own it **cannot tell when a key is still inside**: on
> the car it was built for it locked, and stayed locked, with the fob inside (tested).
> The optional [key sensor](docs/key-sensor.md) fixes that, but it's tested on one car.
> **Keep a spare key outside the car either way. Never run it with a person or pet
> inside. Pause it before a valet, a car wash, or sitting in the switched-off car.**
> The installers are **live from your next stop**; a test-mode installer (log only, never
> locks) exists if you'd rather watch it first.

## Safety

- **Key inside.** Without the key sensor, the lock command it uses has **no key-inside
  interlock**: it locks the car with a fob inside, and the head unit gets **no fob-presence
  signal at all** (verified down to the CAN protocol, [design §8](docs/design.md#8-known-limitations)).
  The blade key lives inside the fob, so that's a real lockout. With the key sensor, it
  holds while it can hear your key in the cabin.
- **No occupant awareness.** It can lock with a person or pet inside, with or without the
  key sensor. On the reference car the inside unlock button didn't work after it locked,
  the front interior handles open the door but set off the alarm, and a rear door with the
  child lock on can't be opened from inside at all. Pause it before leaving anyone in the car.
- **Live from the first stop.** Want to watch first? Use the test-mode installer: it logs
  `WOULD FIRE` and never locks until you switch it to LIVE.
- **One car.** Everything was measured on a single 2022 US EV6 (see
  [Compatibility](#compatibility)). **Re-verify on your own car.** You are responsible for
  your vehicle.

## What it does

After you park, turn the car off, get out and close the door, it locks the car **once**:

- **Without a key sensor:** `LOCK_DELAY` seconds after the door closes (30 by default).
- **With the key sensor:** about 20 seconds after it stops hearing your key, and not at
  all while the key is still in the car.

It only ever **locks**. It has no unlock path, never fights a lock you do yourself, and
arms only after it has seen a real drive. The head unit stays awake only about 3 minutes
from when you open the door to get out; if you linger longer, lock with the fob as usual.
[FAQ: what happens in every edge case](docs/faq.md).

## Choose your setup

| | Without a key sensor | With the key sensor (optional) |
|---|---|---|
| Hardware | none | an ESP32-S3 board on the USB port + a Bluetooth tag on your key ring |
| Installer | `gen5-autolock-install.zip` | `gen5-autolock-install-keysensor.zip` |
| Locks | 30 s after the door closes | ~20 s after your key is out of range |
| Key left inside | **locks it in**: keep a spare outside | holds, doesn't lock |
| Setup guide | [Install](docs/install.md) | [Key sensor](docs/key-sensor.md): parts, flashing the board, first tests |

## Quick start

1. Download the installer for your setup from
   [Releases](https://github.com/s2kwinston/gen5-autolock/releases) and extract it to the
   root of an empty USB stick (FAT32 or exFAT).
2. Start the car, wait for the screen to load, insert the stick, tap **Yes**.
3. Done: it starts by itself every drive and is live from your next stop. With the key
   sensor, finish with [step 5 of its guide](docs/key-sensor.md#5-install-in-the-car).

**Pause / resume:** NEMESIS Manager (three quick presses of **Nav**) → **My Packages →
Gen5 Auto-Lock → Launch**. Settings, test mode, logs and the other USB sticks:
[docs/install.md](docs/install.md).

## Compatibility

| | |
|---|---|
| Vehicle | 2022 US Kia EV6 GT-Line |
| Head unit | Gen5W AVNT (`tcc803x`), Android 4.4.2 (KitKat) |
| Firmware | `CV_E.USA.S5W_M.V015.012.260507` |
| Root | [NEMESIS](https://github.com/xwtk/hmg_nemesis) 1.15 or 1.16.x (tested on 1.15 and 1.16.4) |
| Lock path | `IBCMService.lockDoor(true)` over the MMCAN body relay |
| Key sensor | Waveshare ESP32-S3 Mini + Blue Charm BC011 tag (see [the guide](docs/key-sensor.md)) |

Other EV6 variants *may* work, but the lock behavior, especially with a key inside, was
only established on the setup above. On other firmware the daemon refuses to run until
you accept that firmware ([install details](docs/install.md#install-details)).

## Documentation

- [Install, settings, and on/off](docs/install.md): every zip, the settings table, test mode
- [Key sensor](docs/key-sensor.md): parts, flashing the board, setup, how it decides
- [FAQ](docs/faq.md): the edge cases and what actually happens, plus limitations
- [Design](docs/design.md): the measured facts, state machine, timing, and why
- [Firmware](esp32/README.md): the ESP32 sensor firmware, for developers
- [Changelog](CHANGELOG.md)

## License

[MIT](LICENSE).

## Disclaimer

Not affiliated with, endorsed by, or connected to Kia or Hyundai. This is an independent
modification for a rooted head unit. It controls vehicle locks and is provided with no
warranty of any kind. Rooting your head unit and automating vehicle functions is entirely
at your own risk and may affect your warranty. **You are responsible for your vehicle and
anything locked inside it.**
