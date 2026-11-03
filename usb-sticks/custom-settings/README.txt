===========================================================================
 gen5-autolock — CUSTOM SETTINGS stick (change the lock delay, etc.)
===========================================================================

This USB stick changes gen5-autolock's settings on your car — most often how
long it waits after you close the door before locking.

You do NOT reinstall anything, and it does NOT change whether you're in LIVE or
TEST MODE (the GO LIVE / TEST MODE sticks do that). Only the settings you write
in the file are changed; everything else on the car stays as it is. You only
need it when you want to change a setting; day to day the car locks on its own
with no stick.

WHAT'S ON THE STICK
-------------------
  NEMESIS.data        tells the car to run the script (don't edit)
  apply-config.sh     the script that saves your settings (don't edit)
  gen5-autolock.conf  <-- THIS is the one you edit
  README.txt          this file

HOW TO CHANGE THE LOCK DELAY
----------------------------
 1. On your computer, open  gen5-autolock.conf  in any plain-text editor
    (Notepad is fine).
 2. Change the number on the line

      LOCK_DELAY=30     ->  the seconds after you close the door before it locks
                            (5 to 600; 15–30 feels natural; stay under ~120)

    Save the file. Keep the name exactly  gen5-autolock.conf .
 3. Put all four files back on a USB stick (at the top level of the stick).
 4. In the car: start it, wait for the screen to finish loading, then insert
    the stick.
 5. Tap YES on the prompt. You'll get a "success" message. Remove the stick.

That's it — the new delay is live right away and on every drive after. Your
LIVE/TEST mode and any other settings are untouched.

OTHER SETTINGS
--------------
The file lists the other settings with a '#' in front (switched off). To change
one, remove its '#', set the value, and apply the stick the same way. A line
that still starts with '#' is ignored. You can also force LIVE or TEST MODE
from here by un-commenting one of the DRY_RUN lines — but the dedicated GO LIVE
/ TEST MODE sticks are the simpler way.

IMPORTANT SAFETY NOTE
---------------------
gen5-autolock cannot tell if your key is still inside the car — it will lock a
key in. ALWAYS keep a spare key OUTSIDE the car (on you or at home). Never rely
on it with a person or pet inside.

IF SOMETHING LOOKS WRONG
------------------------
Nothing changes unless you see the "success" message. If you get an error (for
example every line in the file still starts with '#'), the old settings are
still in place and the car's behavior is unchanged.
