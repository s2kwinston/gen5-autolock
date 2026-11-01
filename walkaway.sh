#!/system/bin/sh
###############################################################################
#  walkaway.sh — gen5-autolock: EV6 walk-away auto-lock daemon
#  (REFERENCE IMPLEMENTATION)
#
#  Replicates an OEM-style "walk-away lock" on a head unit whose body module
#  does not offer one: after you park, switch off, get out and shut the door,
#  it locks the car once, a short time later. It never unlocks and never
#  fights a lock you perform yourself.
#
#  *** READ THIS BEFORE YOU RUN IT ***
#    - KEY-INSIDE LOCKOUT RISK. The lock path used here (`bcm 5` =
#      IBCMService.lockDoor) has NO key-inside interlock: on this car it was
#      tested to lock and STAY locked with a key left inside. A software guard
#      is impossible — the head unit receives no fob-presence signal at all
#      (confirmed at the CAN-protocol layer; see docs/design.md §8). If
#      you run this, keep a SPARE key OUTSIDE the car. Never rely on it with a
#      person or pet inside — it has no occupant awareness.
#    - SHIPS IN DRY-RUN. DRY_RUN=1 by default: it logs "WOULD FIRE" and sends
#      no lock. Watch the log across real drives first, then set DRY_RUN=0.
#    - PERSISTENCE IS YOURS TO CHOOSE. Something must start this at each boot
#      (an init service, etc.) — not included here. See docs §7.
#
#  CONFIGURE without editing this file: drop a `gen5-autolock.conf` next to the
#  script (see gen5-autolock.conf.example) to override any knob below.
#  TURN OFF without stopping it: `touch /data/local/tmp/gen5-autolock.off`
#  (delete the file to resume), or set ENABLED=0 in the config.
#
#  Full rationale, state machine and pre-check table: docs/design.md
#
#  Target: 2022 US Kia EV6, firmware CV_E.USA.S5W_M.V015.012.260507,
#          Android 4.4.2 (KitKat, SDK 19), NEMESIS root, isSupportMMCAN=1.
#  Toolbox only — no grep/awk/busybox. Same sh idioms as the proven logger.sh.
#
#  SAFETY INVARIANTS (do not weaken):
#    * Lock only. The ONLY write is `service call com.hkmc.micom.bcm 5 i32 1`
#      (lockDoor true). There is NO unlock path and NO `i32 0` anywhere.
#    * Fires only after a FRESH pre-check passes (IGN off, acc==3, unlocked,
#      every door + trunk closed, driver-exit observed, debounce elapsed).
#    * Arms only after a real drive (sees IGN on first) — a boot-on-approach
#      with the engine off can never be mistaken for a park-and-exit.
#    * One lock per drive cycle, with a small bounded retry; never hammers.
#    * Refuses to run if the framework odex no longer matches the analyzed
#      copy (OTA could change transaction codes).
###############################################################################
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
umask 022

# ---- config DEFAULTS (override them in the config file; do not edit here) ----
POLL_DRIVE=5           # poll interval while IGN on / idle (s)
POLL_ACTIVE=1          # poll interval after IGN off (s) — 1s to catch a quick exit
LOCK_DELAY=30          # seconds after the last door closes before locking (debounce)
POST_FIRE_CONFIRM=5    # wait-and-recheck for mLockState->0 after firing (s)
MAX_FIRES=3            # lock attempts per cycle before giving up
DRIVER_DOOR_ONLY=1     # 1 = arm only on driver-door exit; 0 = any door
MIN_ACC=3              # only fire while mACCStatus == this (off-standby)
DRY_RUN=1              # 1 = log "WOULD FIRE" and send NO lock (safe default)
ENABLED=1              # 0 = installed but inactive (stands down, never arms)
CHECK_ODEX=1           # 1 = refuse to run if the framework hash changed

# ---- paths ----
# Default under /data/nemesis, which SURVIVES reboot. NOT /data/local/tmp — NEMESIS
# clears that on every reboot, which would drop the pause state and the log.
SELF=${0%/*}
NEMESIS_DIR=/data/nemesis
LOG=${GEN5_LOG:-${WALKAWAY_LOG:-$NEMESIS_DIR/gen5-autolock.log}}
OFF_FILE=${GEN5_OFF:-$NEMESIS_DIR/gen5-autolock.off}   # pause flag; survives reboot
REF=${GEN5_REF:-${WALKAWAY_REF:-$SELF/ref}}            # analyzed odex for the hash gate
AUTOMOTIVE_ODEX=/system/framework/automotive.odex
AUTOMOTIVE_SVC_ODEX=/system/framework/automotive-service.odex
# config: prefer a persistent file that survives package updates; else one beside the script
if [ -n "$GEN5_CONF" ]; then CONF=$GEN5_CONF
elif [ -f "$NEMESIS_DIR/gen5-autolock.conf" ]; then CONF=$NEMESIS_DIR/gen5-autolock.conf
else CONF=$SELF/gen5-autolock.conf; fi

say() {
    LINE="$(date '+%Y-%m-%d %H:%M:%S') $*"
    echo "$LINE"
    echo "$LINE" >> "$LOG" 2>/dev/null
}

# make sure the log / pause-flag directories exist (harmless if they already do)
mkdir -p "$NEMESIS_DIR" "${LOG%/*}" "${OFF_FILE%/*}" 2>/dev/null

# ---- load user config (optional; survives script updates) --------------------
# The config file is plain KEY=value sh, sourced as root — keep it root-owned and
# only put the documented knobs in it. See gen5-autolock.conf.example.
if [ -f "$CONF" ]; then
    . "$CONF" 2>/dev/null && say "loaded config: $CONF" || say "WARN: could not source $CONF — using defaults"
fi

# ---- sanitize every knob so a bad config value can never misbehave ----------
clampnum() { # value lo hi default -> sanitized integer
    v=$1
    case "$v" in ''|*[!0-9]*) echo "$4"; return ;; esac
    [ "$v" -lt "$2" ] && v=$2
    [ "$v" -gt "$3" ] && v=$3
    echo "$v"
}
LOCK_DELAY=$(clampnum "$LOCK_DELAY" 5 600 30)
POLL_DRIVE=$(clampnum "$POLL_DRIVE" 1 30 5)
POLL_ACTIVE=$(clampnum "$POLL_ACTIVE" 1 10 1)
POST_FIRE_CONFIRM=$(clampnum "$POST_FIRE_CONFIRM" 1 30 5)
MAX_FIRES=$(clampnum "$MAX_FIRES" 1 10 3)
MIN_ACC=$(clampnum "$MIN_ACC" 0 5 3)
# flags: fail safe — anything but an explicit 0 means the safe setting
[ "$DRY_RUN" = 0 ] || DRY_RUN=1                                  # non-0 => dry-run
{ [ "$ENABLED" = 0 ] && ENABLED=0; } || ENABLED=1
{ [ "$DRIVER_DOOR_ONLY" = 0 ] && DRIVER_DOOR_ONLY=0; } || DRIVER_DOOR_ONLY=1
{ [ "$CHECK_ODEX" = 0 ] && CHECK_ODEX=0; } || CHECK_ODEX=1

# ---- parsed BCM cache globals ----
IGN1="" IGN2="" ACC="" LOCK="" DRV="" PAS="" RL="" RR="" TRUNK="" STOLE="" PANIC=""

read_bcm() {
    DUMP=$(dumpsys com.hkmc.micom.bcm 2>&1)
    IGN1="" IGN2="" ACC="" LOCK="" DRV="" PAS="" RL="" RR="" TRUNK="" STOLE="" PANIC=""
    OLD_IFS="$IFS"
    IFS='
'
    for L in $DUMP; do
        case "$L" in
            *mLockState:*)        LOCK=${L##*: } ;;
            *mDrvOpenedState:*)   DRV=${L##*: } ;;
            *mPasOpenedState:*)   PAS=${L##*: } ;;
            *mRLOpenedState:*)    RL=${L##*: } ;;
            *mRROpenedState:*)    RR=${L##*: } ;;
            *mTrunkOpenedState:*) TRUNK=${L##*: } ;;
            *mIgnition1:*)        IGN1=${L##*: } ;;
            *mIgnition2:*)        IGN2=${L##*: } ;;
            *mACCStatus:*)        ACC=${L##*: } ;;
            *mStole:*)            STOLE=${L##*: } ;;
            *mPanic:*)            PANIC=${L##*: } ;;
        esac
    done
    IFS="$OLD_IFS"
}

# The four passenger doors closed? (0 = closed)
doors_closed() {
    [ "$DRV" = 0 ] && [ "$PAS" = 0 ] && [ "$RL" = 0 ] && [ "$RR" = 0 ]
}
# Doors AND trunk/liftgate closed.
# NOTE: mTrunkOpenedState is treated as the rear liftgate, but it was never seen
# change on-car during testing — VERIFY it actually reads 1 when your liftgate is
# open (open it, `dumpsys com.hkmc.micom.bcm | grep Trunk`) before trusting this.
all_closed() { doors_closed && [ "$TRUNK" = 0 ]; }

# full fire-time pre-check against the CURRENT parsed cache
precheck_ok() {
    [ "$IGN1" = false ] && [ "$IGN2" = false ] &&
    [ "$ACC" = "$MIN_ACC" ] && [ "$LOCK" = 1 ] && all_closed
}

fire_lock() {
    # THE ONLY WRITE IN THIS DAEMON.  i32 1 == lockDoor(true).  Never i32 0.
    say "FIRE attempt $1/$MAX_FIRES: lockDoor(true)  [stole=$STOLE panic=$PANIC acc=$ACC]"
    service call com.hkmc.micom.bcm 5 i32 1 >> "$LOG" 2>&1
}

odex_gate() {
    [ "$CHECK_ODEX" = 1 ] || { say "odex gate DISABLED (CHECK_ODEX=0)"; return 0; }
    if [ ! -f "$REF/automotive.odex" ] || [ ! -f "$REF/automotive-service.odex" ]; then
        say "FATAL: reference odex missing from $REF — refusing to run."
        say "       Copy your head unit's automotive*.odex into $REF (see ref/README.md)."
        return 1
    fi
    cmp "$AUTOMOTIVE_ODEX" "$REF/automotive.odex" >/dev/null 2>&1 || {
        say "FATAL: automotive.odex changed vs analyzed copy — refusing to run."; return 1; }
    cmp "$AUTOMOTIVE_SVC_ODEX" "$REF/automotive-service.odex" >/dev/null 2>&1 || {
        say "FATAL: automotive-service.odex changed vs analyzed copy — refusing to run."; return 1; }
    say "ok: odex hash gate passed"
    return 0
}

###############################################################################
#  main
###############################################################################
say "==== gen5-autolock starting (pid $$)"
say "device=$(getprop ro.product.device) sw=$(getprop ro.build.product)"
say "config: lock_delay=${LOCK_DELAY}s dry_run=$DRY_RUN enabled=$ENABLED driver_door_only=$DRIVER_DOOR_ONLY max_fires=$MAX_FIRES"

odex_gate || exit 1

# wait for Android. A cold boot on this HU can exceed a minute; giving up would
# silently cost a whole drive, so keep waiting (logging) rather than exit, and
# proceed anyway after a generous cap (the loop tolerates an unreadable dump).
N=0
while [ "$(getprop sys.boot_completed)" != 1 ]; do
    [ $((N % 30)) = 0 ] && say "waiting for boot_completed… (${N}s)"
    sleep 2; N=$((N + 2))
    [ $N -ge 300 ] && { say "WARN: boot_completed still unset after ${N}s — proceeding anyway"; break; }
done

# Start in BOOT, not DRIVING: the HU boots on approach-unlock with the engine
# still OFF, so we must NOT treat the driver getting IN (a door open→close) as a
# park-and-exit. BOOT stands down until it has seen a real IGN-on (a drive).
STATE=BOOT
EXIT_SEEN=0
PREV_DRV=0
PREV_ANY=0
FIRES=0
DEB=0            # debounce seconds accumulated
TRUNK_HOLD=0     # paused because the trunk/liftgate is open
PAUSED=0         # paused by the ENABLED knob / off-file toggle

say "entering main loop (STATE=$STATE)"

while :; do
    read_bcm

    # --- cache sanity: if the dump is unreadable, back off and retry ---
    if [ -z "$ACC" ] && [ -z "$IGN1" ]; then
        sleep "$POLL_DRIVE"
        continue
    fi

    # --- global: HU dying (checked even while paused, so we exit cleanly) ---
    if [ "$ACC" = 0 ] || [ "$ACC" = 1 ]; then
        say "acc=$ACC — head unit powering down. STATE=$STATE -> DEAD. exiting."
        exit 0
    fi

    # --- runtime toggle: ENABLED=0 or the off-file pauses us (no restart) ---
    if [ "$ENABLED" != 1 ] || [ -f "$OFF_FILE" ]; then
        if [ "$PAUSED" != 1 ]; then
            PAUSED=1
            say "DISABLED (enabled=$ENABLED off-file=$([ -f "$OFF_FILE" ] && echo yes || echo no)) — standing down; will NOT lock"
        fi
        STATE=BOOT; EXIT_SEEN=0; FIRES=0; DEB=0; TRUNK_HOLD=0
        sleep "$POLL_ACTIVE"
        continue
    elif [ "$PAUSED" = 1 ]; then
        PAUSED=0
        say "ENABLED again — resuming (will arm on the next drive)"
    fi

    # --- global: IGN on resets everything to DRIVING ---
    if [ "$IGN1" = true ]; then
        if [ "$STATE" != DRIVING ]; then
            say "IGN on — reset to DRIVING (was $STATE)"
        fi
        STATE=DRIVING; EXIT_SEEN=0; FIRES=0; DEB=0; TRUNK_HOLD=0
        PREV_DRV=$DRV; PREV_ANY=0
        sleep "$POLL_DRIVE"
        continue
    fi

    # IGN is OFF from here down.
    case "$STATE" in

    BOOT)
        # No drive seen yet and IGN is off. Stand down: a boot-on-approach
        # (HU wakes as you walk up, engine off) must not look like a park-and-
        # exit. The IGN-on handler above promotes BOOT → DRIVING on a real drive.
        :
        ;;

    DRIVING)
        say "IGN off — begin walk-away watch (acc=$ACC lock=$LOCK)"
        STATE=WAIT_EXIT
        EXIT_SEEN=0
        PREV_DRV=$DRV
        ;;

    WAIT_EXIT)
        # detect the exit: driver door (or any door) goes open->closed
        if [ "$DRIVER_DOOR_ONLY" = 1 ]; then
            if [ "$PREV_DRV" = 1 ] && [ "$DRV" = 0 ]; then EXIT_SEEN=1; say "exit seen (driver door closed)"; fi
            PREV_DRV=$DRV
        else
            ANY=0; { [ "$DRV" = 1 ] || [ "$PAS" = 1 ] || [ "$RL" = 1 ] || [ "$RR" = 1 ]; } && ANY=1
            if [ "$PREV_ANY" = 1 ] && [ "$ANY" = 0 ]; then EXIT_SEEN=1; say "exit seen (a door closed)"; fi
            PREV_ANY=$ANY
        fi

        if [ "$EXIT_SEEN" = 1 ] && [ "$ACC" = "$MIN_ACC" ] && [ "$LOCK" = 1 ] && all_closed; then
            STATE=ARMED; DEB=0; TRUNK_HOLD=0
            say "ARMED — debounce ${LOCK_DELAY}s (acc=$ACC lock=$LOCK)"
        fi
        ;;

    ARMED)
        if [ "$LOCK" = 0 ]; then
            say "already locked (lock=0) — standing down. STATE=DONE"
            STATE=DONE
        elif ! doors_closed; then
            # A DOOR reopened — someone may have climbed back in. Require a
            # genuinely fresh driver exit before we can arm again.
            say "a door reopened — back to WAIT_EXIT (need a fresh driver exit)"
            STATE=WAIT_EXIT; EXIT_SEEN=0; DEB=0; TRUNK_HOLD=0; PREV_DRV=$DRV
        elif [ "$TRUNK" != 0 ]; then
            # Trunk/liftgate open but all doors closed = cargo access, not
            # re-entry. HOLD: don't lock while it's open and pause the debounce,
            # but keep EXIT_SEEN so we resume the moment it closes (no fresh exit).
            [ "$TRUNK_HOLD" = 1 ] || { say "trunk/liftgate open — holding (won't lock until it closes)"; TRUNK_HOLD=1; }
            DEB=0
        elif [ "$ACC" != "$MIN_ACC" ]; then
            say "acc=$ACC (not $MIN_ACC) during debounce — aborting this cycle"
            STATE=DONE
        else
            [ "$TRUNK_HOLD" = 1 ] && { say "trunk/liftgate closed — resuming debounce"; TRUNK_HOLD=0; }
            DEB=$((DEB + POLL_ACTIVE))
            if [ "$DEB" -ge "$LOCK_DELAY" ]; then
                # final FRESH pre-check right before firing
                read_bcm
                if precheck_ok; then
                    FIRES=$((FIRES + 1))
                    if [ "$DRY_RUN" = 1 ]; then
                        say "WOULD FIRE $FIRES/$MAX_FIRES (DRY_RUN=1): lockDoor(true) — NO write sent  [acc=$ACC lock=$LOCK stole=$STOLE]"
                        STATE=DONE
                    else
                        fire_lock "$FIRES"
                        sleep "$POST_FIRE_CONFIRM"
                        read_bcm
                        if [ "$LOCK" = 0 ]; then
                            say "confirmed locked (lock=0, stole=$STOLE). STATE=DONE"
                            STATE=DONE
                        elif [ "$FIRES" -ge "$MAX_FIRES" ]; then
                            say "WARN: $FIRES fires, still unlocked (lock=$LOCK). Lock not taking —"
                            say "      cause unknown. NOTE: this path has NO key-inside interlock"
                            say "      (tested), so a refusal is NOT evidence of a key inside."
                            say "      Leaving UNLOCKED. STATE=GAVE_UP"
                            STATE=GAVE_UP
                        else
                            # A refused fire only retries after a GENUINELY NEW exit.
                            # (Re-arming on a timer would re-fire at a driver who just
                            # climbed back in and closed his own door.)
                            say "fire $FIRES did not lock (lock=$LOCK) — need a fresh exit before retrying"
                            STATE=WAIT_EXIT; EXIT_SEEN=0; DEB=0; TRUNK_HOLD=0; PREV_DRV=$DRV
                        fi
                    fi
                else
                    say "final pre-check failed at fire time — re-arming"
                    DEB=0
                fi
            fi
        fi
        ;;

    DONE|GAVE_UP)
        : # stand down; only IGN-on (handled above) resets the cycle
        ;;
    esac

    sleep "$POLL_ACTIVE"
done
