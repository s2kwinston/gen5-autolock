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

After the success message, remove the stick and open that folder on a computer.

-------------------------------------------------------------------------------
TIP — check the liftgate (or a door): BEFORE you insert this stick, OPEN the
rear liftgate (or a door). Then bcm-snapshot.txt will show it, e.g.
"mTrunkOpenedState: 1" for the liftgate or "mDrvOpenedState: 1" for the driver
door. That's how you confirm the car actually reports the liftgate to the head
unit (see the "Test (dry-run first)" section of the project README).
