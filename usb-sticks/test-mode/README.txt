===========================================================================
 gen5-autolock — TEST MODE stick
===========================================================================

Insert this USB in the car (engine on, screen fully loaded) and tap YES.

It switches gen5-autolock to TEST MODE: it keeps running every drive but will
NOT lock the car — it only writes to its log. Use this to try things safely, or
to quickly "disarm" the auto-lock without uninstalling. Your lock-delay and any
other settings are kept.

You'll see a generic "Operation completed successfully" message (that wording is
the car's, not ours). NEMESIS Manager -> Logs will show "set DRY_RUN=1 -> TEST".

Remove the stick after the success message.

To make it lock for real again, use the GO LIVE stick.

(Tip: to turn it off completely rather than just test mode, open NEMESIS Manager
-> Services -> autolock -> Stop, or uninstall the package.)
