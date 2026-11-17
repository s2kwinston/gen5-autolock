# FAQ: the edge cases, and what actually happens

Each answer says how it was established: **on-car** = observed on the 2022 US EV6 it was
built on; **measured** = from that car's own data; **by design** = the daemon's logic,
exercised on the bench against replayed car states (the real script, not a model).
"With the sensor" means the optional [key sensor](key-sensor.md) (`KEY_GATE=1`).

**Jump to:** [Keys](#keys) · [Getting out and back in](#getting-out-and-back-in) ·
[Doors, lids, windows](#doors-lids-windows) · [Timing and power](#timing-and-power) ·
[Software and updates](#software-and-updates) · [Limitations in short](#limitations-in-short)

## Keys

- **I left the key inside.** *Without the sensor:* it locks, and stays locked. **On-car.**
  This lock path has no key-inside interlock and the head unit gets no key signal. The
  blade key is inside the fob: keep a spare key outside the car. *With the sensor:* it
  hears the key in the cabin and doesn't lock. **On-car** (key alone in the cupholder for
  the full 3 minutes: heard 95 % of the time, never silent for more than 5 s).
- **I'm still standing next to the car (unloading, chatting, taking the bins in).**
  *Without the sensor:* it locks after `LOCK_DELAY` anyway. *With the sensor:* it holds
  while it can hear your key and locks about 20 s after it can't. If you're still nearby
  when the head unit goes to sleep (~3 minutes after you opened the door), it doesn't lock:
  use the fob. **On-car.**
- **I park right outside my house.** With the sensor, the board can sometimes hear keys
  through a wall, faintly. Then it holds, and may not lock. **On-car** (parked against the
  house: heard about 40 % of the time from inside; parked farther out: not heard).
- **The sensor is unplugged, or the tag's battery is dead.** With the sensor on, it
  **doesn't auto-lock** and tells you on screen ("key sensor offline" / "key tag not
  detected"). It never falls back to the timed lock. **By design**, and seen on-car.
- **Will someone else's tag hold my car unlocked?** No. The board matches your tag's
  exact address only. **By design.**

## Getting out and back in

- **Someone stays in the car after I get out.** It locks with them inside, with or without
  the key sensor (the sensor tracks your key, not people). **On-car:** a passenger left in
  the front seat couldn't unlock with the inside unlock button; it took the fob. The front
  interior handles open the door but set off the alarm once it's armed, and a **rear door
  with the child lock on can't be opened from inside at all**. There's no occupant signal
  to guard with (measured: the seat-belt sensors never reach the head unit). Pause it
  before leaving anyone in the car.
- **I park, switch off, and just sit there.** Nothing arms: it needs a driver-door
  open→close *after* switch-off. If you sit longer than ~3 minutes after opening the door,
  the head unit has gone to sleep and there's no auto-lock: lock with the fob, same as
  stock. **Measured.**
- **I get out, then get back in.** It can't tell re-entry from a fresh exit: when you
  close the driver door it re-arms and locks with you inside after the delay (with the
  sensor: it holds, because it hears your key). **By design.** Pause it first (NEMESIS
  Manager → My Packages → Gen5 Auto-Lock → Launch).
- **My passenger gets out after me.** By default it **won't auto-lock that stop** unless
  the driver door opens and closes again, and the screen says so. Your passenger might get
  back in and stay, and someone left inside may not be able to unlock it from inside (see
  above). Once they're out, open and shut the driver door, or lock with the fob. If you'd
  rather have it re-arm once every door is closed, set `PASSENGER_REARM=1` with the
  custom-settings stick; with the sensor, it then still counts from when *you* got out.
  A passenger door that was already open when you shut the driver door (getting out
  together) is fine either way. **By design** (bench-tested; the default since 0.2.4. 0.2.3
  re-armed by default).
- **A rear door opens after I've gotten out** (kids getting out after you, a bag from the
  back seat, or putting a child or pet *in*). It **won't auto-lock that stop** unless the
  driver door opens and closes again, and the screen says so. From door data alone,
  someone getting out of the back looks the same as someone being put in, and with the
  child lock on they couldn't open the door from inside. Once everyone's out, open and shut
  the driver door, or lock with the fob. A rear door that was already open when you shut
  the driver door (everyone getting out together) is fine. **By design** (bench-tested;
  since 0.2.3).
- **A bag goes in the back seat before the drive and stays there.** It locks as usual: it
  only watches doors opened *after* you get out, and it can't tell a bag from a child or a
  pet. Check the back seat yourself.
- **I reopen the driver door during the countdown.** It drops back to waiting and starts
  over when the driver door closes again. **By design.**
- **My passenger gets back in after I've walked off.** By default it won't auto-lock that
  stop (see "My passenger gets out after me"). With `PASSENGER_REARM=1`, once the doors are
  shut it locks with them inside (see "Someone stays in the car" above). **By design.**
- **The head unit wakes as I walk up (approach unlock).** That isn't a drive: it arms only
  after it has seen ignition on, so a boot-on-approach can never lock you in while you get
  seated. **By design.**
- **Quick stop: switch off, then restart without getting out.** Ignition on resets
  everything; nothing fires. **By design.**

## Doors, lids, windows

- **The liftgate is open when I get out, or I open it after.** It waits / holds, and
  resumes the countdown the moment the liftgate closes; no second exit needed. **On-car**,
  both shapes.
- **The frunk/hood is open.** Same hold, read from the head unit's system log (it isn't in
  the normal vehicle data). **On-car.** A fob *shut inside* the frunk is still a lockout:
  the hood is closed by then and the frunk has no outside release. The sensor may not hear
  a key in the frunk either.
- **A window or the sunroof is open.** It locks anyway; the head unit has no usable
  window/sunroof value. **Measured.** Same as a stock lock.
- **I lock it myself first (fob or handle).** It sees the car is locked and stands down;
  it never double-sends. **On-car.**
- **Does it ever unlock?** No. There is no unlock code in the daemon: the only vehicle
  write is the single lock command, and every bench scenario asserts no unlock is ever
  sent. **By design.**
- **Will the alarm arm?** Yes, like any lock: the car arms ~30 s after locking; opening a
  door from inside after that trips it. **On-car.**
- **Charging.** Plug in *before* it locks; if it locks first, the charge port won't pop:
  unlock, plug in, and it stays unlocked for that stop (one lock per stop). **By design.**

## Timing and power

- **How long does the car stay lockable after I switch off?** About **3 minutes from when
  you open the driver door** to get out; then the head unit goes to sleep and nothing runs.
  A door held open while you unload uses that time up, and a lock sent in the last few
  seconds may not take. **Measured** (41 logged stops: never sooner than 180 s after
  ignition off, usually 180–200 s, sometimes longer; one stop where the door stayed open
  ~3 minutes left only 51 s after it closed; one lock sent 6 s before power-down didn't take).
- **I set a very long delay.** The head unit sleeps before it fires → no lock. The delay
  is clamped to 5–600 s; keep it ≤ ~90. **Measured.**
- **The head unit reboots mid-cycle.** The daemon restarts, stands down, and waits for the
  next drive; a reboot never produces a lock. **On-car.**
- **Valet, car wash, dealer.** Pause it first. Otherwise a fob left with the car gets
  locked in the moment someone closes the door and walks off (without the sensor), or the
  car stays unlocked (with it).

## Software and updates

- **Kia pushes a software update.** It refuses to run (`FATAL: framework is not a verified
  build`) until you consciously re-pin with the ref-odex stick: an update could renumber
  the lock command. **On-car** for the pass; the refusal path **by design**.
- **NEMESIS updates.** The package and its running service survived the NEMESIS 1.15 →
  1.16.4 update untouched. **On-car.**

## Limitations in short

- **Key inside:** without the sensor, it can lock a key in. Keep a spare outside the car.
- **No occupant detection.** Never rely on it with a person or pet inside.
- **Only while the head unit is awake:** ~3 minutes from opening the driver door.
- **Liftgate and hood are guarded; windows and sunroof are not.**
- **Getting back in can lock you in** (without the sensor).
- **Tested on one car.** Other model years, firmwares or markets may behave differently.

The measured facts and the full reasoning are in [design.md](design.md).
