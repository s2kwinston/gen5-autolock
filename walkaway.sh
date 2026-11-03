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
#    - PERSISTENCE: the NEMESIS package registers this as a service NEMESIS
#      starts at every boot (no /system init change). Standalone? Arrange your
#      own boot launch — see docs/design.md §7.
#
#  CONFIGURE without editing this file: put a `gen5-autolock.conf` at
#  /data/nemesis/ (or beside the script) to override any knob below — see
#  gen5-autolock.conf.example. It is PARSED for known keys, never executed.
#  TURN OFF without stopping it: `touch /data/nemesis/gen5-autolock.off`
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
#      every door, the liftgate and the hood closed, driver-exit observed,
#      debounce elapsed).
#    * Arms only after a real drive (sees IGN on first) — a boot-on-approach
#      with the engine off can never be mistaken for a park-and-exit.
#    * One lock per drive cycle, with a small bounded retry; never hammers.
#    * Refuses to run unless the framework odex matches a verified build (md5)
#      or a reference the user pinned (an OTA could change transaction codes).
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
HOOD_GUARD=1           # 1 = also hold while the hood/frunk is open (read from logcat)

# ---- paths ----
# Default under /data/nemesis, which SURVIVES reboot. NOT /data/local/tmp — NEMESIS
# clears that on every reboot, which would drop the pause state and the log.
SELF=${0%/*}
NEMESIS_DIR=/data/nemesis
LOG=${GEN5_LOG:-${WALKAWAY_LOG:-$NEMESIS_DIR/gen5-autolock.log}}
OFF_FILE=${GEN5_OFF:-$NEMESIS_DIR/gen5-autolock.off}   # pause flag; survives reboot
# prefer a persistent ref dir that survives package updates; else ./ref (standalone)
if [ -n "$GEN5_REF" ]; then REF=$GEN5_REF
elif [ -n "$WALKAWAY_REF" ]; then REF=$WALKAWAY_REF
elif [ -f "$NEMESIS_DIR/gen5-autolock-ref/automotive.odex" ]; then REF=$NEMESIS_DIR/gen5-autolock-ref
else REF=$SELF/ref; fi            # analyzed odex for the hash gate
FW=${GEN5_FRAMEWORK:-/system/framework}
AUTOMOTIVE_ODEX=$FW/automotive.odex
AUTOMOTIVE_SVC_ODEX=$FW/automotive-service.odex
# md5 of the framework files on the build(s) the lock transaction was verified
# against (space-separated lists; add a build = add a hash to each). md5 is an
# OTA tripwire here, not a security boundary.
#   CVEV.USA.0000.V015.012.260507  (2022 US Kia EV6 GT-Line, Gen5W)
KNOWN_MD5_AUTOMOTIVE="efbfceed274a0b58d092e89aeaa8c66e"
KNOWN_MD5_AUTOMOTIVE_SVC="33a30843e149a3d604ecc6957fd25d46"
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

# ---- load user config (optional; survives updates) --------------------------
# PARSED, not sourced. We read ONLY the documented KEY=value knobs and ignore
# every other line, so the config can never execute code as root — even if some
# other process managed to write it. Values are range-checked below regardless.
load_config() {
    [ -f "$CONF" ] || return 0
    while read -r line || [ -n "$line" ]; do
        case "$line" in ''|\#*|';'*) continue ;; esac
        case "$line" in *=*) : ;; *) continue ;; esac   # must be KEY=value
        key=${line%%=*}; val=${line#*=}
        # keep only the leading digits: this strips an inline "# comment", trailing
        # spaces and a CRLF's CR using ONLY [!0-9] (works on toolbox mksh — no printf,
        # no [[:space:]]). Every knob is numeric; a non-numeric value becomes "" -> default.
        val=${val%%[!0-9]*}
        case "$key" in
            POLL_DRIVE)        POLL_DRIVE=$val ;;
            POLL_ACTIVE)       POLL_ACTIVE=$val ;;
            LOCK_DELAY)        LOCK_DELAY=$val ;;
            POST_FIRE_CONFIRM) POST_FIRE_CONFIRM=$val ;;
            MAX_FIRES)         MAX_FIRES=$val ;;
            DRIVER_DOOR_ONLY)  DRIVER_DOOR_ONLY=$val ;;
            MIN_ACC)           MIN_ACC=$val ;;
            DRY_RUN)           DRY_RUN=$val ;;
            ENABLED)           ENABLED=$val ;;
            CHECK_ODEX)        CHECK_ODEX=$val ;;
            HOOD_GUARD)        HOOD_GUARD=$val ;;
            *) say "config: ignoring unknown key '$key'" ;;
        esac
    done < "$CONF"
    say "loaded config: $CONF"
}
load_config

# ---- sanitize every knob so a bad config value can never misbehave ----------
clampnum() { # value lo hi default -> sanitized integer
    v=$1
    case "$v" in ''|*[!0-9]*) echo "$4"; return ;; esac
    case "$v" in ???????*) echo "$4"; return ;; esac   # >7 digits: absurd -> default
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
{ [ "$HOOD_GUARD" = 0 ] && HOOD_GUARD=0; } || HOOD_GUARD=1

# ---- parsed BCM cache globals ----
IGN1="" IGN2="" ACC="" LOCK="" DRV="" PAS="" RL="" RR="" TRUNK="" STOLE="" PANIC=""
HOOD=""   # hood/frunk switch from logcat: 1 open, 0 closed, "" unknown (counts as closed)

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
# Hood/frunk: NOT in dumpsys, but every stock BCM client logs the hood switch on
# each door event ("D/BCMCanManager: mDoorStatus.mHoodSwitchState<n>"), so the
# log is a TX-free read of it (verified on-car 2026-11-01: 1 with the frunk open,
# and the hood's own open/close each raise an event). Last line wins; HOOD keeps
# its value between reads. Only called while IGN is off (the ring-buffer read is
# cheap but not free). "" = no door event in the log yet = treated as closed;
# every exit logs one, so it is known by the time we can arm.
read_hood() {
    [ "$HOOD_GUARD" = 1 ] || { HOOD=""; return 0; }
    HL=$(logcat -d -s BCMCanManager:D 2>/dev/null)
    OLD_IFS="$IFS"
    IFS='
'
    for L in $HL; do
        case "$L" in
            *mHoodSwitchState*) H=${L##*mHoodSwitchState}; H=${H%%[!0-9]*}; [ -n "$H" ] && HOOD=$H ;;
        esac
    done
    IFS="$OLD_IFS"
}

# Monotonic seconds since boot from /proc/uptime (verified on this HU). Immune to the
# wall clock being set after boot (the HU starts at a 2015 default and syncs later).
# "" if unreadable — then the debounce counts polls instead.
UPTIME_FILE=${GEN5_UPTIME:-/proc/uptime}
now_s() {
    set -- $(cat "$UPTIME_FILE" 2>/dev/null); n=${1%%.*}
    case "$n" in ''|*[!0-9]*) echo "" ;; *) echo "$n" ;; esac
}

# Lids closed: liftgate from the cache (mTrunkOpenedState — verified on-car
# 2026-11-01: reads 1 with the rear liftgate open) and the hood from logcat.
lids_closed() { [ "$TRUNK" = 0 ] && [ "$HOOD" != 1 ]; }
# Doors AND lids closed.
all_closed() { doors_closed && lids_closed; }

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

# ---- framework hash gate ----------------------------------------------------
# The lock transaction (bcm 5) was verified against specific framework builds. An
# OTA could renumber it, so refuse to run unless the live framework is known-good:
#   1. its md5 matches a verified build (toolbox `md5`; zero user steps), or
#   2. it is byte-identical to a reference the user PINNED in $REF (ref-odex stick)
#      — the conscious "I accept this firmware" path for other builds / after an OTA.
md5_of() { # file -> 32-hex md5, or "" (toolbox `md5` prints "<hash>  <file>")
    set -- $(md5 "$1" 2>/dev/null)
    case "$1" in
        ????????????????????????????????) case "$1" in *[!0-9a-f]*) echo "" ;; *) echo "$1" ;; esac ;;
        *) echo "" ;;
    esac
}
in_list() { # value list -> 0 if value is one of the space-separated list items
    [ -n "$1" ] && case " $2 " in *" $1 "*) return 0 ;; esac; return 1
}
known_build() {
    in_list "$(md5_of "$AUTOMOTIVE_ODEX")" "$KNOWN_MD5_AUTOMOTIVE" &&
    in_list "$(md5_of "$AUTOMOTIVE_SVC_ODEX")" "$KNOWN_MD5_AUTOMOTIVE_SVC"
}
odex_gate() {
    [ "$CHECK_ODEX" = 1 ] || { say "odex gate DISABLED (CHECK_ODEX=0)"; return 0; }
    if known_build; then
        say "ok: odex gate passed (framework matches a verified build)"
        return 0
    fi
    if [ ! -f "$REF/automotive.odex" ] || [ ! -f "$REF/automotive-service.odex" ]; then
        say "FATAL: framework is not a verified build and no pinned reference in $REF — refusing to run."
        say "       sw=$(getprop ro.build.product) md5=$(md5_of "$AUTOMOTIVE_ODEX")/$(md5_of "$AUTOMOTIVE_SVC_ODEX")"
        say "       To accept THIS firmware anyway: insert the ref-odex USB stick (or copy"
        say "       $FW/automotive*.odex into $REF). See ref/README.md."
        return 1
    fi
    cmp "$AUTOMOTIVE_ODEX" "$REF/automotive.odex" >/dev/null 2>&1 || {
        say "FATAL: automotive.odex changed vs the pinned reference — refusing to run."; return 1; }
    cmp "$AUTOMOTIVE_SVC_ODEX" "$REF/automotive-service.odex" >/dev/null 2>&1 || {
        say "FATAL: automotive-service.odex changed vs the pinned reference — refusing to run."; return 1; }
    say "ok: odex gate passed (framework matches your pinned reference in $REF)"
    return 0
}

###############################################################################
#  main
###############################################################################
say "==== gen5-autolock starting (pid $$)"
say "device=$(getprop ro.product.device) sw=$(getprop ro.build.product)"
say "config: lock_delay=${LOCK_DELAY}s dry_run=$DRY_RUN enabled=$ENABLED driver_door_only=$DRIVER_DOOR_ONLY max_fires=$MAX_FIRES hood_guard=$HOOD_GUARD"
say "paths: conf=$CONF off_file=$OFF_FILE log=$LOG"

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
DEB=0            # debounce: polls counted (fallback when the clock is unusable)
ARM_T=""         # debounce: wall-clock second we armed / resumed at
LID_HOLD=0       # paused because the liftgate or the hood is open
EXIT_MSG=""      # pending "exit seen" line (logged once the hood has been read)
WAIT_MSG=0       # "lid open at exit — waiting" logged once per exit
PAUSED=0         # paused by the ENABLED knob / off-file toggle
ALIVE=0          # have we seen a live ACC yet? (a cold-boot cache can read 0/1)

say "entering main loop (STATE=$STATE)"

while :; do
    read_bcm

    # --- cache sanity: if the dump is unreadable, back off and retry ---
    if [ -z "$ACC" ] && [ -z "$IGN1" ]; then
        sleep "$POLL_DRIVE"
        continue
    fi

    # mark the HU "alive" once we've seen a real ACC (off-standby/transition/on)
    case "$ACC" in 3|4|5) ALIVE=1 ;; esac

    # --- global: HU dying vs. not-yet-up ------------------------------------
    # A low ACC (0/1) means power-down ONLY after we've seen it alive. At cold
    # boot the cache can read 0/1 before the bus is up; exiting then would cost a
    # whole drive (mode=background never restarts), so wait rather than exit.
    if [ "$ACC" = 0 ] || [ "$ACC" = 1 ]; then
        if [ "$ALIVE" = 1 ]; then
            say "acc=$ACC — head unit powering down. STATE=$STATE -> DEAD. exiting."
            exit 0
        fi
        sleep "$POLL_DRIVE"; continue
    fi

    # --- runtime toggle: ENABLED=0 or the off-file pauses us (no restart) ---
    if [ "$ENABLED" != 1 ] || [ -f "$OFF_FILE" ]; then
        if [ "$PAUSED" != 1 ]; then
            PAUSED=1
            say "DISABLED (enabled=$ENABLED off-file=$([ -f "$OFF_FILE" ] && echo yes || echo no)) — standing down; will NOT lock"
        fi
        STATE=BOOT; EXIT_SEEN=0; FIRES=0; DEB=0; LID_HOLD=0
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
        STATE=DRIVING; EXIT_SEEN=0; FIRES=0; DEB=0; LID_HOLD=0
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
        # Detect the exit: driver door (or any door) goes open->closed. NO hood read
        # on these polls — the log dump costs seconds on this HU (measured 2026-11-02:
        # polls with it ran 2–5 s apart) and a brief door open->close must not fall
        # between polls. The hood only matters once the exit has been seen.
        if [ "$DRIVER_DOOR_ONLY" = 1 ]; then
            if [ "$PREV_DRV" = 1 ] && [ "$DRV" = 0 ]; then EXIT_SEEN=1; EXIT_MSG="driver door closed"; WAIT_MSG=0; fi
            PREV_DRV=$DRV
        else
            ANY=0; { [ "$DRV" = 1 ] || [ "$PAS" = 1 ] || [ "$RL" = 1 ] || [ "$RR" = 1 ]; } && ANY=1
            if [ "$PREV_ANY" = 1 ] && [ "$ANY" = 0 ]; then EXIT_SEEN=1; EXIT_MSG="a door closed"; WAIT_MSG=0; fi
            PREV_ANY=$ANY
        fi

        if [ "$EXIT_SEEN" = 1 ]; then
            read_hood       # exit seen: now the lids matter (a slow poll is fine here)
            [ -n "$EXIT_MSG" ] && { say "exit seen ($EXIT_MSG)  [drv=$DRV pas=$PAS rl=$RL rr=$RR trunk=$TRUNK hood=${HOOD:-?}]"; EXIT_MSG=""; }
            if [ "$ACC" = "$MIN_ACC" ] && [ "$LOCK" = 1 ] && all_closed; then
                STATE=ARMED; DEB=0; LID_HOLD=0; ARM_T=$(now_s)
                say "ARMED — debounce ${LOCK_DELAY}s (acc=$ACC lock=$LOCK trunk=$TRUNK hood=${HOOD:-?} doors=$DRV$PAS$RL$RR)"
            elif [ "$WAIT_MSG" != 1 ] && ! lids_closed; then
                LID=hood; [ "$TRUNK" != 0 ] && LID=trunk/liftgate
                say "$LID open at exit — waiting for it to close before arming"; WAIT_MSG=1
            fi
        fi
        ;;

    ARMED)
        read_hood
        if [ "$LOCK" = 0 ]; then
            say "already locked (lock=0) — standing down. STATE=DONE"
            STATE=DONE
        elif ! doors_closed; then
            # A DOOR reopened. Go back to WAIT_EXIT for another driver-door
            # open->close. NOTE: this is NOT occupant protection — if someone
            # climbs back IN via the driver door and shuts it, that reads as a
            # fresh exit and we WILL arm and lock with them inside after the
            # debounce. Pause the daemon before sitting in a switched-off car;
            # the interior handle always opens a locked door from within.
            say "a door reopened — back to WAIT_EXIT (waiting for a driver-door cycle)"
            STATE=WAIT_EXIT; EXIT_SEEN=0; DEB=0; LID_HOLD=0; PREV_DRV=$DRV
        elif ! lids_closed; then
            # Liftgate or hood open but all doors closed = cargo/frunk access, not
            # re-entry. HOLD: don't lock while it's open and pause the debounce,
            # but keep EXIT_SEEN so we resume the moment it closes (no fresh exit).
            if [ "$LID_HOLD" != 1 ]; then
                LID=hood; [ "$TRUNK" != 0 ] && LID=trunk/liftgate
                say "$LID open — holding (won't lock until it closes)"; LID_HOLD=1
            fi
            DEB=0; ARM_T=""
        elif [ "$ACC" != "$MIN_ACC" ]; then
            say "acc=$ACC (not $MIN_ACC) during debounce — aborting this cycle"
            STATE=DONE
        else
            [ "$LID_HOLD" = 1 ] && { say "lid closed — resuming debounce"; LID_HOLD=0; ARM_T=$(now_s); }
            # Debounce in REAL seconds (monotonic /proc/uptime), so a slow poll can't
            # stretch LOCK_DELAY and a clock sync can't skip it; fall back to counting
            # polls if uptime is unreadable.
            NOW=$(now_s)
            if [ -n "$NOW" ] && [ -n "$ARM_T" ]; then
                WAITED=$((NOW - ARM_T))
                # uptime is monotonic, so this can't happen — but never trust a
                # negative wait: fall back to counting polls for this cycle.
                if [ "$WAITED" -lt 0 ]; then
                    say "uptime went backwards (${WAITED}s) — counting polls for this cycle instead"
                    ARM_T=""; DEB=0; WAITED=0
                fi
            else DEB=$((DEB + POLL_ACTIVE)); WAITED=$DEB; fi
            if [ "$WAITED" -ge "$LOCK_DELAY" ]; then
                # final FRESH pre-check right before firing. The hood read takes
                # seconds, so do it FIRST and read the cache LAST: door/lock state
                # must be the freshest thing we hold when the lock goes out.
                read_hood; read_bcm
                [ "$HOOD_GUARD" = 1 ] && [ -z "$HOOD" ] && say "note: hood state unknown (no door event in the log yet) — treated as closed"
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
                            STATE=WAIT_EXIT; EXIT_SEEN=0; DEB=0; LID_HOLD=0; PREV_DRV=$DRV
                        fi
                    fi
                else
                    say "final pre-check failed at fire time — re-arming"
                    DEB=0; ARM_T=$(now_s)
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
