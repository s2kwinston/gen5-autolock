===========================================================================
 gen5-autolock — REF ODEX stick (only if the log says "not a verified build")
===========================================================================

WHY
The daemon has a safety gate: it refuses to run unless the car's software
("framework") is a build it was verified on. That protects you if a Kia update
ever renumbers the command it sends — an unchecked update could turn "lock the
doors" into something else. On a 2022 US EV6 (firmware 260507) the gate passes
by itself and you do NOT need this stick.

You need it only if the daemon's log says "FATAL: framework is not a verified
build": another model/firmware, or your car received a Kia update. This stick
then PINS your own head unit's framework as accepted: it copies two files from
the car's system area into /data/nemesis/gen5-autolock-ref/ and restarts the
daemon. Pinning does not verify the lock command on that software — it means
"I accept this firmware". Nothing under /system is modified. It never locks or
unlocks.

HOW
  1. Install the package first (see the project README).
  2. Start the car, wait for the screen to fully load.
  3. Insert this USB stick, tap YES, wait for "Operation completed successfully."
  4. Remove the stick. The daemon is now running — in TEST MODE (dry-run) until
     you insert the GO LIVE stick.

AFTER A KIA SOFTWARE UPDATE
If the car's software is updated later, the daemon will stop itself (the gate
tripped — exactly what it's for) and the log will say the framework changed.
Running this stick again re-pins the reference to the NEW software and it says
"REPLACED". Only do that if you are sure the lock command is unchanged on the
new software; otherwise leave it stopped. (Verified so far on firmware 260507.)

CHECKING IT WORKED
Insert the GET-LOG stick (usb-sticks/get-log/) and open gen5-autolock.log on a
computer: the latest start-up lines should show the odex gate passing and no
"FATAL" line. Or in the NEMESIS Manager, Services -> autolock shows running.

Prefer a shell? The same thing by hand:
  cp /system/framework/automotive.odex         /data/nemesis/gen5-autolock-ref/
  cp /system/framework/automotive-service.odex /data/nemesis/gen5-autolock-ref/
  nemesis service start gen5.autolock/autolock
