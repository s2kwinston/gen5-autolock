===========================================================================
 gen5-autolock — GET LOG stick
===========================================================================

Insert this USB in the car (engine on, screen loaded) and tap YES.

It makes NO change to the car and never locks or unlocks. It only COPIES onto
this stick, into a timestamped folder (gen5-autolock-logs/<date-time>/):

  * gen5-autolock.log    the daemon's own log — what it has been doing, incl.
                         "WOULD FIRE" lines in test mode and its start-up
                         "dry_run=0/1" line (which tells you LIVE vs TEST)
  * gen5-autolock.conf   your current settings
  * bcm-snapshot.txt     a one-shot reading of the car's door / trunk / ignition
                         state (a cache read — it sends nothing to the car)
  * service-log/         the service's own output, if present

Key sensor diagnostics (useful even without one):
  * key_state.txt        the sensor's latest status (last time the tag was heard)
  * key_trace.log*       every line the sensor board sent, this start and the 3
                         before it (the last hour or two of each)
  * boot_id.txt, tty.txt which head-unit start this is; the serial ports present
  * usb-diag.txt         USB devices and drivers, and which program has each
                         serial port open
  * dmesg.txt            the head unit's kernel log
  * logcat.txt           the head unit's full system log (a few MB)

PRIVACY: dmesg.txt and especially logcat.txt are the head unit's own logs. They
can contain things like your phone's name, Wi-Fi network names, navigation or
location lines, and the car's VIN. Read them (or delete them) before you post
or send this folder to anyone. gen5-autolock.log and key_trace.log are usually
all that's needed to ask for help.

After the success message, remove the stick and open that folder on a computer.

-------------------------------------------------------------------------------
TIP — check the liftgate (or a door): BEFORE you insert this stick, OPEN the
rear liftgate (or a door). Then bcm-snapshot.txt will show it, e.g.
"mTrunkOpenedState: 1" for the liftgate or "mDrvOpenedState: 1" for the driver
door. That's how you confirm the car actually reports the liftgate to the head
unit (see "Optional: test mode first" in the project's docs/install.md).
