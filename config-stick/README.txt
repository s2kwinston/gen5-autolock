===========================================================================
 gen5-autolock — CONFIG STICK (change the settings)
===========================================================================

This little USB stick changes gen5-autolock's settings on your car — how long
it waits before locking, and whether it's in test mode or really locking.

You do NOT reinstall anything. This just drops your settings into the car. You
only need it when you want to change a setting; day to day the car locks on its
own with no stick.

WHAT'S ON THE STICK
-------------------
  NEMESIS.data        tells the car to run the script (don't edit)
  apply-config.sh     the script that saves your settings (don't edit)
  gen5-autolock.conf  <-- THIS is the one you edit
  README.txt          this file

HOW TO CHANGE A SETTING
-----------------------
 1. On your computer, open  gen5-autolock.conf  in any plain-text editor
    (Notepad is fine).
 2. Change the two settings at the top:

      DRY_RUN=1     ->  change to  DRY_RUN=0   to make it LOCK FOR REAL
                        (leave at 1 for "test mode": runs but never locks)

      LOCK_DELAY=30 ->  the seconds after you close the door before it locks
                        (any number from 5 to 600; 30 is a good start)

    Save the file. Keep the name exactly  gen5-autolock.conf .
 3. Put all four files back on a USB stick (at the top level of the stick).
 4. In the car: start it, wait for the screen to finish loading, then insert
    the stick.
 5. Tap YES on the prompt. You'll get a "success" message. Remove the stick.

That's it — the new settings are live right away and on every drive after.

FIRST TIME / GOING LIVE
-----------------------
When you first install gen5-autolock it starts in TEST MODE (DRY_RUN=1): it
runs every drive but does NOT lock, it only writes to a log. Drive normally a
few times, make sure nothing odd happens, then use this stick with DRY_RUN=0
to switch it to really locking.

IMPORTANT SAFETY NOTE
---------------------
gen5-autolock cannot tell if your key is still inside the car — it will lock a
key in. ALWAYS keep a spare key OUTSIDE the car (on you or at home). Never rely
on it with a person or pet inside.

IF SOMETHING LOOKS WRONG
------------------------
Nothing changes unless you see the "success" message. If you get an error, the
old settings are still in place. The car's behavior is unchanged until a
successful apply.
