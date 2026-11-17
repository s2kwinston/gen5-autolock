# Key sensor (optional): don't lock with the key inside

On its own, gen5-autolock can't tell whether your key is still in the car: the head unit
gets no key signal at all, so it locks on a timer. The **key sensor** is an add-on that
fixes that. A small Bluetooth tag rides on your key ring, and a small ESP32 board plugged
into the head unit's USB port listens for it. The car then locks **only after your key
has actually left** — and holds off while it can still hear the key in the cabin.

> [!IMPORTANT]
> Field-tested on **one car** (2022 US EV6), with one tag and one board. Keep a **spare key
> outside the car** anyway. If the sensor is unplugged, offline, or can't hear your tag,
> the car simply **doesn't auto-lock** (it never falls back to the timed lock).

**Contents:** [Parts](#what-you-need) · [Set up the tag](#1-set-up-the-tag) ·
[Find its address](#2-find-the-tags-address) · [Flash the board](#3-flash-the-board) ·
[Check it on the computer](#4-check-it-on-the-computer) · [Install in the car](#5-install-in-the-car) ·
[First tests](#6-first-tests) · [Everyday use](#everyday-use) · [How it decides](#how-it-decides) ·
[Limitations](#limitations-and-known-issues) · [Troubleshooting](#troubleshooting)

## What you need

| Part | Tested | Notes |
|---|---|---|
| Bluetooth key tag | [Blue Charm Beacons BC011 MultiBeacon](https://link.amazon/B03fw6GIw) | Must keep a **fixed address** (the BC011 does). AirTag-style trackers rotate their address for privacy and **won't work**. |
| ESP32-S3 board | [Waveshare ESP32-S3 Mini (ESP32-S3FH4R2)](https://link.amazon/B0cfigVZC) | **The tested board.** Its RGB LED isn't used by the firmware, so it stays dark. |
| *or* | [Adafruit QT Py ESP32-S3, 4 MB flash / 2 MB PSRAM](https://www.adafruit.com/product/5700) | Same chip (ESP32-S3FH4R2) and the same firmware build, so it should behave identically, but it hasn't been tested on a car. |
| *or* | [Seeed Studio XIAO ESP32S3](https://link.amazon/B0f1eFTdo) | An ESP32-S3 with its own USB port and an **external antenna (attach it)**. A different chip variant (8 MB flash / 8 MB PSRAM) with its **own board settings** (step 3). The firmware builds for it, but it hasn't been tested on a car. |
| USB-A to USB-C cable | any **data** cable | Many cheap cables are charge-only and the board won't show up at all. Short is better. |
| To set it up | a computer, and an **Android** phone | The phone is only for reading the tag's address (iPhones hide it). |

<sub>Some links above are affiliate links: as an Amazon Associate, the author earns from
qualifying purchases, at no extra cost to you.</sub>

**Buying a different board?** It must be an **ESP32-S3** (or another ESP32 with BLE) that
uses the chip's **own USB port**. Avoid boards with a separate USB-to-serial chip
(CH340, CH343, CP2102): the head unit only has the standard USB serial driver and won't
see them. The car's reader also only opens a board that identifies itself with USB vendor
id `239a` or `303a`; the settings in step 3 give you one of those, but another board's
own Arduino setting may not.

## 1. Set up the tag

1. Put a battery in the tag and set it up with the maker's app (see the card in the box).
2. Set it to advertise about **once a second** (1000 ms). The tested tag did; much slower
   and the board misses it more often, much faster and the battery drains sooner.
3. Optional: give it a name you'll recognize (e.g. `MyKeys`). The board ignores the name;
   it only matches the address.
4. Put it on the key ring you actually carry.

## 2. Find the tag's address

The address looks like `AA:BB:CC:DD:EE:FF`. On an **Android** phone:

1. Install **nRF Connect for Mobile** (Nordic Semiconductor) from the Play Store.
2. Open it and tap **Scan**.
3. Hold the tag right next to the phone. It's the entry with the name you gave it (or the
   strongest signal, around −40 to −60 dBm). The address is shown under the name.
4. Write it down exactly.

iPhones don't show Bluetooth addresses to apps, so borrow an Android phone for this step.

## 3. Flash the board

You do this once, on a computer, with the free **Arduino IDE**. It takes about 15 minutes,
most of it downloading.

**Get the tools (once):**
1. Install **Arduino IDE 2** from <https://www.arduino.cc/en/software>.
2. **File → Preferences → Additional boards manager URLs**, add
   `https://espressif.github.io/arduino-esp32/package_esp32_index.json` and click OK.
3. **Tools → Board → Boards Manager**: search `esp32`, install **esp32 by Espressif
   Systems** (version 3.x).
4. **Tools → Manage Libraries**: search `NimBLE-Arduino`, install **NimBLE-Arduino by
   h2zero** (version 2.x).

**Put your tag's address in the firmware:**

5. Download this project (**Code → Download ZIP** on the GitHub page) and unzip it.
6. In the Arduino IDE, **File → Open** `esp32/key_scanner/key_scanner.ino`.
7. Find this line near the top and put your address between the quotes:
   ```cpp
   static const char*    TAG_ADDRESS = "00:00:00:00:00:00";
   ```
   For example `"A1:B2:C3:D4:E5:F6"`. Upper or lower case both work. Save.

**Choose the board settings** (Tools menu), then pick the board's port under
**Tools → Port**:

| Setting | Waveshare or Adafruit | Seeed XIAO ESP32S3 |
|---|---|---|
| Board | `Adafruit QT Py ESP32-S3 (4M Flash 2M PSRAM)` | `XIAO_ESP32S3` |
| USB Mode | `USB-OTG (TinyUSB)` | **`Hardware CDC and JTAG`** |
| USB CDC On Boot | `Enabled` | `Enabled` |

Yes, choose the Adafruit entry even for the Waveshare board: both boards use the same
chip, the firmware doesn't use any board-specific pins, and this exact setting is what the
tested sensor runs. (It also makes the board identify itself with a USB id the car's
reader looks for.)

For the XIAO, use its own board entry but switch **USB Mode** to `Hardware CDC and JTAG`:
in that mode it identifies itself with Espressif's USB id, which the car's reader accepts.
With `USB-OTG (TinyUSB)` it would use Seeed's own id, and the car would ignore it
("key sensor offline").

**Upload:**

8. Plug the board into the computer and click **Upload** (the → arrow).
9. If it says it can't connect, put the board into download mode by hand: hold the
   **BOOT** button, tap **RESET** (RST), let go of **BOOT**. On the XIAO they're the tiny
   buttons marked **B** and **R**. Choose the port again (it may change), click **Upload**
   again.
10. When it says *Done uploading*, tap **RESET** or unplug and replug the board.

The board's LED stays off; that's normal. The serial lines in the next step are its only
sign of life.

## 4. Check it on the computer

1. **Tools → Serial Monitor**, set the speed to **115200 baud**.
2. Within a few seconds you should see `# key_scanner up`, then a new line every 2.5 s.
3. With the tag next to the board: `KEY 1 -45 12 8` (the second number is the signal, about
   −40 to −70 nearby).
4. Take the tag to another room: mostly `KEY 0 0 ...` lines.

| You see | It means |
|---|---|
| `KEY 1 ...` with the tag close | Working. Go to the car. |
| Only `KEY 0 ...`, even with the tag touching the board | The address is wrong, or the tag isn't advertising. Recheck step 2. |
| `# TAG_ADDRESS is not set` | You uploaded without editing the address (step 7). |
| `ERR ...` lines only | The Bluetooth scan isn't running. Re-upload; if it persists, try another board. |
| Nothing at all | Wrong port or speed, or a charge-only cable. |

When it works, **close the Serial Monitor, then unplug the board and plug it back in**
(or tap **RESET**) before you take it to the car. Some serial tools leave an ESP32 in its
download mode when they let go of the port, and then it looks dead in the car; a
replug always brings it back to normal.

## 5. Install in the car

The head unit has **one USB port**. The installer stick and the board take turns in it.

1. Download **`gen5-autolock-install-keysensor.zip`** from the
   [Releases](https://github.com/s2kwinston/gen5-autolock/releases) page and extract it to
   the root of a USB stick (FAT32 or exFAT).
2. Car on (parked), wait for the screen to finish loading, insert the stick, tap **Yes**.
   The screen says *NEMESIS operation completed successfully*. Already have gen5-autolock
   installed? The same stick updates it and switches the sensor on; your other settings
   are kept.
3. **Restart the service:** open the NEMESIS Manager (three quick presses of **Nav**) →
   **Services → `autolock` → Stop**, then **Start**.
4. Take the stick out and plug the board in with the data cable. A *device not supported*
   media pop-up is expected (the media player can't use the board; the auto-lock can).
   Dismiss it.
5. Start the car with the key on you. Within about a minute you should see
   **"key sensor ready - key tag detected"**. That message confirms the whole chain: the
   new version is running, the sensor is on, the board is connected, and it hears your tag.

## 6. First tests

Carry the **spare key** for both. Don't open the frunk or the liftgate during them.

1. **Key left inside.** Main key in the cupholder, spare in your pocket. Get out, shut
   the driver door, walk away. **It must not lock.** About 3 minutes after you opened the
   door the head unit goes to sleep and it stops trying. Lock with the spare.
2. **Walk away.** Take the main key, get out, shut the door, walk off. It locks about
   **20 seconds after the board stops hearing your key** (on the test car: 31 s after the
   door closed). Check the handle or the app afterwards. Don't press the fob while you
   wait, or you won't know which one locked it.

If either test does something else, pull the log with the **get-log** stick (unplug the
board first) and read it before relying on the sensor.

## Everyday use

Nothing to do: keep the board plugged in and the tag on your keys. Messages you may see
(small and brief, at the bottom of the screen):

| Message | When | What it means |
|---|---|---|
| key sensor ready - key tag detected | once per start | All good. |
| key sensor offline - auto-lock will not fire | while driving | The board isn't connected or isn't reporting. No auto-lock this stop. |
| key sensor offline - not auto-locking | at the stop | Same, noticed when it was time to lock. |
| key tag not detected - auto-lock will not fire | while driving | The board works but has never heard your tag this trip (tag battery? key ring left at home?). |
| key tag not detected - not auto-locking | at the stop | Same, noticed when it was time to lock. |
| key tag not heard at exit - not auto-locking | at the stop | The tag was already quiet when you got out, so it can't tell that it left. |

To use any NEMESIS stick (settings, get-log), unplug the board, use the stick, then plug
the board back in. While the board is out, the car won't auto-lock.

## How it decides

The board prints a line every 2.5 s: *heard the tag* or *listened and didn't hear it*. The
car locks only if your tag was **heard as you got out**, and the board then reported **20
seconds of silence** in an unbroken feed. Anything else holds: still heard (key inside, or
you're standing next to the car), never heard, already silent when you got out, the board
dropping out or reconnecting (the 20 s starts over), or no fresh data at all. The hold
isn't final: if the key leaves later, it locks then — as long as the head unit is still
awake.

The 20 s comes from field data: across four long drives and a 3-minute key-in-the-cupholder
test, the longest the board went without hearing a key that was in the car was 7.5 s.

## Timing: the 3-minute window

The car keeps the head unit awake for **about 3 minutes from when you open the driver door**
to get out. After that nothing on the head unit runs, so nothing can lock. A lock sent in
the last few seconds before it sleeps may not take. In practice:

- **Get out and walk away:** locks about 20–40 s after the door closes.
- **Unload with the door open, chat next to the car, take the bins in:** it holds while it
  can hear your key. If you're still nearby when the window runs out, it won't lock. Use
  the fob, same as stock.

Settings (custom-settings stick): `KEY_GONE_DEBOUNCE` (default 20, the seconds of silence)
and `LOCK_DELAY` (default 30, the minimum wait after the door closes). With the sensor,
`LOCK_DELAY` rarely matters; the test car runs `LOCK_DELAY=15`. Don't raise
`KEY_GONE_DEBOUNCE` much: 45 s missed real locks on the test car because the head unit fell
asleep first.

## Limitations and known issues

- **One car, one tag, one board.** Re-check on your own car (the two tests above).
- **The board can hear through a wall.** Park right outside your house with the keys just
  inside, and it may still hear them faintly and hold. On the test car this happened when
  parked right against the house; parked farther out, it didn't.
- **Standing near the car** holds the lock while it hears your key, and past the 3-minute
  window it won't lock at all.
- **Reopening a different door after you get out** (passenger or rear, to grab something)
  makes it wait for the driver door to open and close again. If you don't use the driver
  door again, it won't lock that stop.
- **Hazard flash ("key left inside"):** log-only (`HAZARD_LIVE=0`) and untested on a car.
  It also can't yet tell "key inside" from "you standing next to the car". Leave it off.
- The "key sensor ready" message accepts a reading up to 10 s old, so unplugging the board
  right before you start the car can still show it. The lock decision has the same 10 s
  limit, so it can't lock on stale data.
- The board's detailed history (`key_trace.log*` on the get-log stick) keeps only the first
  hour after each start.
- The board runs warm (around 70 °C on the chip after 20 minutes): normal, but give it
  airflow. **Never** power it from a battery left in a parked car. Handle the bare board by
  its edges; a case or tape over the exposed pads avoids static damage.

## Turning it off

- **Back to the plain timed lock:** custom-settings stick with `KEY_GATE=0`. Then it locks
  even with the key inside again — keep a spare outside the car.
- **Pause everything:** NEMESIS Manager → My Packages → Gen5 Auto-Lock → Launch.

Unplugging the board doesn't turn the sensor off: it just means "sensor offline", so the
car stops auto-locking until it's back.

## Troubleshooting

| Problem | Check |
|---|---|
| "key sensor offline" | Board plugged in? Data cable (not charge-only)? Flashed and showing `KEY` lines on a computer? A board with a CH340/CP2102 chip won't work. Last used with a serial monitor? Unplug and replug it (see step 4). |
| The board vanished or showed up as a new port after closing a serial monitor | It's in download mode. Unplug and replug it, or tap **RESET**. |
| "key tag not detected" | Wrong address in the firmware, tag battery, or the tag isn't on the keys you carry. |
| "key tag not heard at exit" | The tag went quiet before you got out: usually a weak tag battery. |
| No messages at all | You installed the plain installer (the sensor is off), or skipped the Stop/Start in step 5. |
| Doesn't lock at home | See "hears through a wall" above. Pull the log: `key_trace.log` shows what the board heard. |

The **get-log** stick copies the daemon log, the sensor state, the board's recent history
(`key_trace.log*`) and USB diagnostics onto the stick. It changes nothing on the car. It
also copies the head unit's own system logs (`logcat.txt`, `dmesg.txt`), which can contain
personal details: check them before you share the folder.
