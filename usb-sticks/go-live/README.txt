===========================================================================
 gen5-autolock — GO LIVE stick
===========================================================================

Insert this USB in the car (engine on, screen fully loaded) and tap YES.

It switches gen5-autolock from TEST MODE to LIVE: from now on it will ACTUALLY
LOCK the car when you park, switch off, get out and close the door. Your
lock-delay and any other settings are kept exactly as they were.

You'll see a generic "Operation completed successfully" message (that wording is
the car's, not ours, and looks the same for every stick). The new mode is saved
and takes effect right away.

To be certain it went live: the daemon records the mode in its own log at
/data/nemesis/gen5-autolock.log, where its next start-up line reads "dry_run=0"
(LIVE). If that ever reads "dry_run=1", it is still in test mode.

Remove the stick after the success message. You do NOT need it again day to day.

To go back to test mode, use the TEST MODE stick.

-------------------------------------------------------------------------------
IMPORTANT: gen5-autolock cannot tell if your key is still inside — it WILL lock
a key in. Always keep a SPARE KEY OUTSIDE the car. Never rely on it with a
person or pet inside.
