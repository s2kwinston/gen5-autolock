# key_scanner firmware

Firmware for the optional BLE key sensor: an ESP32-S3 board on the head unit's USB port
that listens for the Bluetooth tag on your key ring. **Step-by-step setup, parts and
flashing for non-developers: [`docs/key-sensor.md`](../docs/key-sensor.md).** This page is
the short version for people who already use Arduino tools.

## What it does

Every 2.5 s it listens for your tag for 1.2 s and prints one line over USB serial
(115200 baud, LF line endings):

```
KEY 1 <rssi> <seq> <n>     tag heard in this window (best dBm; n = devices heard)
KEY 0 0 <seq> <n>          listened for the whole window, tag not heard
ERR <reason> <ms> <seq>    the scan didn't run properly (not evidence of absence)
# ...                      comments (startup, "TAG_ADDRESS not set", reboot notice)
```

`key-reader.sh` on the head unit turns those lines into `/data/nemesis/key_state`; every
lock / hold decision is made by `walkaway.sh`, not here. Anything other than a steady
stream of `KEY` lines makes the head unit fail safe (no lock).

## Before you build

Set your tag's address in `key_scanner/key_scanner.ino`:

```cpp
static const char*    TAG_ADDRESS = "AA:BB:CC:DD:EE:FF";
```

Until it's set, the board prints `# TAG_ADDRESS is not set` and no `KEY` lines.

Library: **NimBLE-Arduino** (h2zero), 2.x. Core: **esp32** by Espressif, 3.x.
(Developed with core 3.3.12, NimBLE-Arduino 2.5.2.)

## Build and flash (arduino-cli)

Use this FQBN for both boards; it's the tested build:

```
esp32:esp32:adafruit_qtpy_esp32s3_n4r2:USBMode=default,CDCOnBoot=cdc
```

| Board | Status |
|---|---|
| Waveshare ESP32-S3 Mini (ESP32-S3FH4R2) | **Tested on the car** with the FQBN above |
| Adafruit QT Py ESP32-S3, 4 MB flash / 2 MB PSRAM (also ESP32-S3FH4R2) | Same chip and build; not tested on a car |

Both boards carry the same ESP32-S3FH4R2, and the firmware uses no board pins (radio and
USB only), so the QT Py board definition fits the Waveshare too. It also gives the board
Adafruit's USB vendor id `239a`, which is what the tested setup reports. The generic
`esp32:esp32:esp32s3:USBMode=default,CDCOnBoot=cdc,FlashSize=4M,PSRAM=enabled` also
compiles (it reports Espressif's `303a`, also accepted) but hasn't been run on a car.

```sh
FQBN="esp32:esp32:adafruit_qtpy_esp32s3_n4r2:USBMode=default,CDCOnBoot=cdc"
arduino-cli core install esp32:esp32
arduino-cli lib install NimBLE-Arduino
arduino-cli compile --fqbn "$FQBN" key_scanner
arduino-cli upload  --fqbn "$FQBN" -p <port> key_scanner
```

`USBMode=default` is USB-OTG (TinyUSB) and `CDCOnBoot=cdc` gives a plain CDC serial
device: no USB drive, no REPL. On the reference head unit it appears as `/dev/ttyACM2`
(its built-in cellular modem already owns `ttyACM0`/`ttyACM1`). `key-reader.sh` picks the
board by USB vendor id (`239a` from the build above, or `303a` Espressif) and never opens
anything else.

If an upload can't connect, put the board in download mode by hand: hold **BOOT**, tap
**RESET**, release **BOOT**, upload again, then tap **RESET** (or unplug and replug) to start
the new firmware.

## Notes

- The onboard LED is not used. The serial lines are the only sign of life.
- Address-only matching, so it never reacts to someone else's tag. The tag must use a
  fixed (static) address; tags that rotate their address for privacy (AirTag-style
  trackers) won't work.
- `setMaxResults(0)` means "callbacks only" in NimBLE 2.x, so `getResults()` returns an
  empty list. The tag is detected in the scan callbacks. Don't "simplify" this to
  reading the results list: that version always reports `KEY 0`.
- A loop watchdog (~5 s) reboots the board if the BLE stack ever wedges, instead of
  going silent. Silence already makes the head unit fail safe.
- Serial monitors: arduino-esp32's USB CDC treats a particular DTR/RTS sequence as
  "reboot into the bootloader". Opening the port with DTR alone (RTS low) and then
  closing it can leave the board in ROM download mode (a new port, `303a:1001`), which
  looks dead. Assert both DTR and RTS in your own tools, and unplug/replug (or tap RESET)
  after any serial session before the board goes back in the car. Linux `cdc_acm` on the
  head unit raises and drops both lines together, so the car can't trigger it.
- The scanning logic is the code that ran on the test car. The address handling
  (`TAG_ADDRESS` lower-casing and the not-set guard) was added for publishing and is
  compile-checked only so far.
- It runs warm (around 70 °C on the chip after 20 minutes of scanning): normal. Give it
  some airflow; never power it from a battery left in a parked car.
