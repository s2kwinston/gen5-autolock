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
#      tested to lock and STAY locked with a key left inside. The head unit
#      itself receives no fob-presence signal at all (confirmed at the
#      CAN-protocol layer; see docs/design.md §8). The OPTIONAL key-gate
#      (KEY_GATE=1) adds an external ESP32 that listens for a BLE tag on your
#      key ring — see the key-presence section below. Without it, keep a SPARE
#      key OUTSIDE the car. Never rely on it with a person or pet inside — it
#      has no occupant awareness.
#    - DRY_RUN=1 is the BUILT-IN default: with no config it logs "WOULD FIRE"
#      and sends no lock. The standard installer seeds DRY_RUN=0 (live from the
#      next stop); the test-mode installer seeds 1. The USB sticks flip it.
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
#    * Writes are LOCK and (optionally) a lights-only HAZARD flash, nothing else:
#        - lock:   `service call com.hkmc.micom.bcm 5 i32 1` (lockDoor true). NO unlock,
#                  NO `i32 0` on tx 5, ever.
#        - hazard: `service call com.hkmc.micom.bcm 6 i32 2` (startFindingCar mode 2 =
#                  C_HazardFromIBOX, lights), then `6 i32 0` (stop) HAZARD_SECS later.
#                  NEVER `6 i32 1` — that is the PANIC alarm.
#                  Off by default (HAZARD_LIVE=0 -> dry-run) until verified on-car.
#    * With KEY_GATE=1 the lock fires only after the key tag was heard at the exit AND
#      then went silent for KEY_GONE_DEBOUNCE (it LEFT). Still heard, never heard,
#      silent already at the exit, or sensor down/stale/other-boot => NO lock (fail-safe).
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
# ---- key-presence (ESP32 sensor via key-reader.sh); see docs/key-sensor.md ----
KEY_GATE=0             # 0 = legacy blind lock (DEFAULT, unchanged behavior). 1 = require the
                       #     key to have LEFT the cabin before locking (the key-inside safety fix).
KEY_GONE_DEBOUNCE=20   # s of continuous silence that means the key has left (worst in-car gap seen: 7.5 s)
FLASH_DELAY=60         # s the key must STILL be heard after exit before the "left inside" flash
KEY_STALE=10           # reader beat older than this = board/reader down = OFFLINE (fail-safe)
KEY_BOOT_GRACE=60      # s after start before a missing/silent sensor is worth a warning toast
KEY_READY_TOAST=1      # 1 = one "key sensor ready" toast per boot when the tag is first heard
KEY_HOLD_MAX=180       # s after the exit to keep waiting for the key to leave; then give up for
                       #     this stop (the head unit is usually asleep by then: ~3 min after the
                       #     driver door opens)
KEY_FLASH_FRESH=12     # (fixed) the "left inside" flash needs the tag heard within this many s
                       #     (worst in-cabin gap measured 8.3 s); not a config knob
KEY_READY_FRESH=3      # (fixed) "key sensor ready" needs a board line within this many s (the
                       #     board prints every 2.5 s); a board unplugged just before the start
                       #     must not say "ready". Not a config knob
HAZARD_LIVE=0          # 0 = hazard flash is DRY-RUN (log only). Untested on a car: leave 0
HAZARD_SECS=3          # s between hazard start and stop (~2-3 blinks), 1-15

# ---- paths ----
# Default under /data/nemesis, which SURVIVES reboot. NOT /data/local/tmp — NEMESIS
# clears that on every reboot, which would drop the pause state and the log.
SELF=${0%/*}
NEMESIS_DIR=/data/nemesis
LOG=${GEN5_LOG:-${WALKAWAY_LOG:-$NEMESIS_DIR/gen5-autolock.log}}
OFF_FILE=${GEN5_OFF:-$NEMESIS_DIR/gen5-autolock.off}   # pause flag; survives reboot
KEY_STATE=${GEN5_KEY_STATE:-$NEMESIS_DIR/key_state}    # written by key-reader.sh (presence feed)
BOOT_ID_FILE=${GEN5_BOOT_ID:-/proc/sys/kernel/random/boot_id}  # key_state uptimes are per-boot
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
            KEY_GATE)          KEY_GATE=$val ;;
            KEY_GONE_DEBOUNCE) KEY_GONE_DEBOUNCE=$val ;;
            FLASH_DELAY)       FLASH_DELAY=$val ;;
            KEY_STALE)         KEY_STALE=$val ;;
            KEY_BOOT_GRACE)    KEY_BOOT_GRACE=$val ;;
            KEY_READY_TOAST)   KEY_READY_TOAST=$val ;;
            KEY_HOLD_MAX)      KEY_HOLD_MAX=$val ;;
            HAZARD_LIVE)       HAZARD_LIVE=$val ;;
            HAZARD_SECS)       HAZARD_SECS=$val ;;
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
# key-presence knobs
KEY_GONE_DEBOUNCE=$(clampnum "$KEY_GONE_DEBOUNCE" 10 600 20)
FLASH_DELAY=$(clampnum "$FLASH_DELAY" 10 600 60)
KEY_STALE=$(clampnum "$KEY_STALE" 3 120 10)
KEY_BOOT_GRACE=$(clampnum "$KEY_BOOT_GRACE" 10 600 60)
HAZARD_SECS=$(clampnum "$HAZARD_SECS" 1 15 3)
KEY_HOLD_MAX=$(clampnum "$KEY_HOLD_MAX" 60 1800 180)
{ [ "$KEY_GATE" = 1 ] && KEY_GATE=1; } || KEY_GATE=0            # OFF unless explicitly 1
{ [ "$HAZARD_LIVE" = 1 ] && HAZARD_LIVE=1; } || HAZARD_LIVE=0   # dry-run unless explicitly 1
{ [ "$KEY_READY_TOAST" = 0 ] && KEY_READY_TOAST=0; } || KEY_READY_TOAST=1

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
    # THE PRIMARY WRITE.  i32 1 == lockDoor(true).  Never i32 0 on tx 5.
    say "FIRE attempt $1/$MAX_FIRES: lockDoor(true)  [stole=$STOLE panic=$PANIC acc=$ACC]"
    service call com.hkmc.micom.bcm 5 i32 1 >> "$LOG" 2>&1
}

# ---- key-presence (ESP32 sensor via key-reader.sh -> $KEY_STATE) -------------
KEY_SEEN="" KEY_BEAT="" KEY_RSSI="" KEY_BOOT=""
MY_BOOT=""; read MY_BOOT < "$BOOT_ID_FILE" 2>/dev/null   # "" if this kernel has no boot_id
read_key_state() {
    KEY_SEEN=""; KEY_BEAT=""; KEY_RSSI=""; KEY_BOOT=""; KEY_SINCE=""
    [ -f "$KEY_STATE" ] || return 0
    while read -r kl || [ -n "$kl" ]; do
        case "$kl" in
            seen_uptime=*) KEY_SEEN=${kl#seen_uptime=} ;;
            rssi=*)        KEY_RSSI=${kl#rssi=} ;;
            beat=*)        KEY_BEAT=${kl#beat=} ;;
            since=*)       KEY_SINCE=${kl#since=} ;;
            boot=*)        KEY_BOOT=${kl#boot=} ;;
        esac
    done < "$KEY_STATE"
}
# Classify the sensor feed (call read_key_state first). Sets KEY_P to exactly one of:
#   OFFLINE  no clock / no file / beat stale, garbled or AHEAD of the clock / file from
#            another boot / no feed start -> board or reader down: can't know -> never lock
#   NOTAG    board alive but the tag has never been heard this boot (dead tag battery?)
#   GONE     the board OBSERVED KEY_GONE_DEBOUNCE s of silence on one continuous feed:
#            beat - max(last sighting, feed start) >= debounce. Measured up to the last
#            beat, NOT up to now: a board that died or dropped off USB can never "observe"
#            silence (its beat freezes), and silence from before a reconnect never counts.
#   HERE     anything else with a live feed (heard recently, or not yet enough observed
#            silence) -> hold
# Also sets KEY_SI (integer uptime of the last sighting) for the exit check and KEY_AGE
# (s since the last sighting) for the flash. Globals, not echo: no subshell swallows them.
key_presence() {
    KEY_P=OFFLINE; KEY_SI=""; KEY_AGE=""
    nb=$(now_s)
    [ -n "$nb" ] || return 0
    [ -n "$MY_BOOT" ] && [ "$KEY_BOOT" != "$MY_BOOT" ] && return 0     # another boot's file
    bi=${KEY_BEAT%%.*}
    case "$bi" in ''|*[!0-9]*) return 0 ;; esac
    [ $((nb - bi)) -lt 0 ] && return 0                                  # beat from the future
    [ $((nb - bi)) -gt "$KEY_STALE" ] && return 0                       # reader stale/dead
    fs=${KEY_SINCE%%.*}
    case "$fs" in ''|*[!0-9]*) return 0 ;; esac                        # no feed start: garbled
    [ "$fs" -gt "$bi" ] && return 0
    case "$KEY_SEEN" in ''|-) KEY_P=NOTAG; return 0 ;; esac            # alive, never heard
    si=${KEY_SEEN%%.*}
    case "$si" in ''|*[!0-9]*) return 0 ;; esac
    [ "$si" -gt "$bi" ] && return 0                                     # sighting after the beat
    KEY_SI=$si; KEY_AGE=$((nb - si))
    from=$si; [ "$fs" -gt "$from" ] && from=$fs                       # observed silence starts here
    if [ $((bi - from)) -ge "$KEY_GONE_DEBOUNCE" ]; then KEY_P=GONE; else KEY_P=HERE; fi
    return 0
}
# Lights-only hazard flash (NOT the panic alarm): start, wait HAZARD_SECS, stop.
# startFindingCar(2) = C_HazardFromIBOX (lights); mode 0 = stop (the vendor's own
# stopFindingCar() is startFindingCar(0)); mode 1 = PANIC — NEVER sent.
# DRY-RUN until HAZARD_LIVE=1 (untested on a car; see docs/key-sensor.md).
fire_hazard() {
    if [ "$HAZARD_LIVE" = 1 ]; then
        say "FLASH: key left in cabin — hazard lights ${HAZARD_SECS}s (startFindingCar 2, then 0)  [stole=$STOLE]"
        service call com.hkmc.micom.bcm 6 i32 2 >> "$LOG" 2>&1
        sleep "$HAZARD_SECS"
        service call com.hkmc.micom.bcm 6 i32 0 >> "$LOG" 2>&1
    else
        say "WOULD FLASH (HAZARD_LIVE!=1): key left in cabin — hazard lights (startFindingCar 2, then 0)"
    fi
}
# Transient on-screen message via the vendor HMI toast (am broadcast) — the same path
# NEMESIS uses from an sh service. Backgrounded, boot-gated. Every caller passes a fixed
# literal message, and "$msg" reaches am as one quoted argument (no shell re-parse), so
# no sanitizer is needed (an earlier bracket-pattern one was a mksh-parsing risk).
framework_up() { [ "$(getprop sys.boot_completed)" = 1 ]; }
toast() {
    msg=$1; [ -n "$msg" ] || return 0
    framework_up || return 0
    # Backgrounded so a wedged Activity Manager can never stall the lock loop; the
    # message is occasional (once per cycle) and the HU reboots each drive, so a
    # detached am needs no watchdog.
    am broadcast -a com.hkmc.intent.action.TOAST -e com.hkmc.intent.extra.TOAST_MESSAGE "$msg" --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 &
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
say "key-gate: key_gate=$KEY_GATE key_gone_debounce=${KEY_GONE_DEBOUNCE}s flash_delay=${FLASH_DELAY}s key_stale=${KEY_STALE}s boot_grace=${KEY_BOOT_GRACE}s hazard_live=$HAZARD_LIVE hazard_secs=${HAZARD_SECS}s key_state=$KEY_STATE boot_id=${MY_BOOT:-none}"
say "paths: conf=$CONF off_file=$OFF_FILE log=$LOG"

odex_gate || exit 1

# Key-gate: start the key sensor reader (key-reader.sh, beside this script). It is not
# a NEMESIS service of its own; it holds a single-instance lock, so a daemon restart
# (settings stick, Manager Start) just finds the running one and leaves it be. It only
# READS the ESP32 on the USB port — it never talks to the car.
if [ "$KEY_GATE" = 1 ]; then
    KR_STARTED=0
    for kr in "$GEN5_KEY_READER" "$SELF/key-reader.sh" "$NEMESIS_DIR/apps/gen5.autolock/key-reader.sh"; do
        [ -n "$kr" ] && [ -f "$kr" ] || continue
        sh "$kr" </dev/null >/dev/null 2>&1 &
        say "key-gate: started the key sensor reader ($kr, pid $!)"
        KR_STARTED=1; break
    done
    [ "$KR_STARTED" = 1 ] || say "key-gate: WARNING key-reader.sh not found — the sensor will read OFFLINE, so it will NOT auto-lock"
fi

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
PREV_RL=0        # rear doors last poll (a rear door opening after the exit cancels it)
PREV_RR=0
FIRES=0
DEB=0            # debounce: polls counted (fallback when the clock is unusable)
ARM_T=""         # debounce: wall-clock second we armed / resumed at
LID_HOLD=0       # paused because the liftgate or the hood is open
EXIT_MSG=""      # pending "exit seen" line (logged once the hood has been read)
WAIT_MSG=0       # "lid open at exit — waiting" logged once per exit
PAUSED=0         # paused by the ENABLED knob / off-file toggle
ALIVE=0          # have we seen a live ACC yet? (a cold-boot cache can read 0/1)
FLASHED=0        # key-gate: fired the "key left inside" flash this cycle?
KEY_TOASTED=0    # key-gate: shown a "not auto-locking" toast this cycle?
DRIVE_WARNED=0   # key-gate: shown a "sensor/tag problem" toast this drive?
READY_SAID=0     # key-gate: announced "sensor ready" this boot?
EXIT_T=""        # key-gate: uptime of the exit that armed this cycle
KEEP_EXIT_T=0    # 1 = re-arming after a passenger/rear door: keep the DRIVER's exit as EXIT_T
LOOP_T=$(now_s)  # key-gate: uptime the main loop started (warning grace period)

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
        STATE=DRIVING; EXIT_SEEN=0; FIRES=0; DEB=0; LID_HOLD=0; FLASHED=0; KEY_TOASTED=0
        PREV_DRV=$DRV; PREV_ANY=0; KEEP_EXIT_T=0; PREV_RL=$RL; PREV_RR=$RR
        # Key-gate status while you are still IN the car (at the lock point you've already
        # walked away): one "ready" toast per boot the first time the tag is heard, and one
        # warning per drive if the sensor is down or the tag isn't heard. Warnings wait
        # KEY_BOOT_GRACE after start (the board and reader need time to come up).
        if [ "$KEY_GATE" = 1 ]; then
            read_key_state; key_presence
            if [ "$KEY_P" = HERE ]; then
                # "ready" needs a LIVE board: a beat within KEY_READY_FRESH, not just within
                # KEY_STALE (a board unplugged right before the start must not say "ready").
                RBA=""; RNOW=$(now_s); RBI=${KEY_BEAT%%.*}
                case "$RBI" in ''|*[!0-9]*) ;; *) [ -n "$RNOW" ] && RBA=$((RNOW - RBI)) ;; esac
                if [ "$READY_SAID" != 1 ] && [ -n "$RBA" ] && [ "$RBA" -le "$KEY_READY_FRESH" ]; then
                    say "key-gate: sensor ready — key tag heard (rssi $KEY_RSSI)"
                    [ "$KEY_READY_TOAST" = 1 ] && toast "key sensor ready - key tag detected"
                    READY_SAID=1
                fi
            elif [ "$DRIVE_WARNED" != 1 ]; then
                NOWK=$(now_s)
                if [ -n "$NOWK" ] && [ -n "$LOOP_T" ] && [ $((NOWK - LOOP_T)) -ge "$KEY_BOOT_GRACE" ]; then
                    case "$KEY_P" in
                        OFFLINE)
                            say "key-gate: sensor OFFLINE while driving — auto-lock will NOT fire this stop  [seen=$KEY_SEEN beat=$KEY_BEAT boot=$KEY_BOOT]"
                            toast "key sensor offline - auto-lock will not fire"; DRIVE_WARNED=1 ;;
                        NOTAG|GONE)
                            say "key-gate: key tag NOT heard while driving ($KEY_P) — auto-lock will NOT fire unless it is heard at exit  [seen=$KEY_SEEN]"
                            toast "key tag not detected - auto-lock will not fire"; DRIVE_WARNED=1 ;;
                    esac
                fi
            fi
        fi
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
        PREV_DRV=$DRV; PREV_RL=$RL; PREV_RR=$RR
        DRIVE_WARNED=0   # next drive gets its own warning
        ;;

    WAIT_EXIT)
        # Detect the exit: driver door (or any door) goes open->closed. NO hood read
        # on these polls — the log dump costs seconds on this HU (measured 2026-11-02:
        # polls with it ran 2–5 s apart) and a brief door open->close must not fall
        # between polls. The hood only matters once the exit has been seen.
        # A REAR door that opens after the exit was seen (someone may have just been put in
        # the back: rear child locks mean they can't open it from inside) cancels the exit:
        # no arming until the driver door opens and closes again. A rear door already open
        # when the driver door closed (people getting out together) doesn't count.
        REAR_NEW=0
        { { [ "$PREV_RL" = 0 ] && [ "$RL" = 1 ]; } || { [ "$PREV_RR" = 0 ] && [ "$RR" = 1 ]; }; } && REAR_NEW=1
        PREV_RL=$RL; PREV_RR=$RR
        if [ "$EXIT_SEEN" = 1 ] && [ "$REAR_NEW" = 1 ]; then
            say "a rear door opened after you got out — won't arm until the driver door opens and closes again"
            EXIT_SEEN=0; KEEP_EXIT_T=0; EXIT_MSG=""
        fi
        DRV_EDGE=0; [ "$PREV_DRV" = 1 ] && [ "$DRV" = 0 ] && DRV_EDGE=1
        PREV_DRV=$DRV
        # A real driver-door exit becomes the key gate's reference again (see KEEP_EXIT_T).
        [ "$DRV_EDGE" = 1 ] && KEEP_EXIT_T=0
        if [ "$DRIVER_DOOR_ONLY" = 1 ]; then
            if [ "$DRV_EDGE" = 1 ]; then EXIT_SEEN=1; EXIT_MSG="driver door closed"; WAIT_MSG=0; fi
        else
            ANY=0; { [ "$DRV" = 1 ] || [ "$PAS" = 1 ] || [ "$RL" = 1 ] || [ "$RR" = 1 ]; } && ANY=1
            if [ "$PREV_ANY" = 1 ] && [ "$ANY" = 0 ]; then EXIT_SEEN=1; EXIT_MSG="a door closed"; WAIT_MSG=0; fi
            PREV_ANY=$ANY
        fi

        if [ "$EXIT_SEEN" = 1 ]; then
            read_hood       # exit seen: now the lids matter (a slow poll is fine here)
            [ -n "$EXIT_MSG" ] && { say "exit seen ($EXIT_MSG)  [drv=$DRV pas=$PAS rl=$RL rr=$RR trunk=$TRUNK hood=${HOOD:-?}]"; EXIT_MSG=""; }
            if [ "$ACC" = "$MIN_ACC" ] && [ "$LOCK" = 1 ] && all_closed; then
                STATE=ARMED; DEB=0; LID_HOLD=0; ARM_T=$(now_s); FLASHED=0; KEY_TOASTED=0
                # Re-arming after a passenger/rear door: the key gate keeps measuring from the
                # DRIVER's exit (the key was heard then); the debounce restarts from now.
                { [ "$KEEP_EXIT_T" = 1 ] && [ -n "$EXIT_T" ]; } || EXIT_T=$ARM_T
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
            # A DOOR reopened. NOTE: none of this is occupant protection — someone who
            # climbs back in and shuts the door gets locked in after the debounce. On the
            # reference car the inside unlock button doesn't work after this lock, the
            # front interior handles open the door (and trip the alarm), and a rear door
            # with the child lock on can't be opened from inside at all. Pause the daemon
            # before sitting in a switched-off car.
            if [ "$RL" = 1 ] || [ "$RR" = 1 ]; then
                # A REAR door after the driver got out: someone may have just been put in
                # the back. Old rule: no arming until the driver door opens and closes again.
                say "a rear door opened after you got out — won't arm until the driver door opens and closes again"
                STATE=WAIT_EXIT; EXIT_SEEN=0; KEEP_EXIT_T=0; DEB=0; LID_HOLD=0; PREV_DRV=$DRV; PREV_RL=$RL; PREV_RR=$RR
            elif [ "$DRV" = 0 ]; then
                # Only the front passenger door: a passenger getting out after the driver.
                # Re-arm as soon as every door is closed again — no new driver-door cycle
                # needed — and keep the driver's exit as the key gate's reference.
                say "the passenger door opened — will re-arm when all doors are closed"
                STATE=WAIT_EXIT; EXIT_SEEN=1; KEEP_EXIT_T=1; WAIT_MSG=0; DEB=0; LID_HOLD=0; PREV_DRV=$DRV; PREV_RL=$RL; PREV_RR=$RR
            else
                # The driver door itself: wait for it to close again (a fresh exit).
                say "the driver door reopened — back to WAIT_EXIT (waiting for it to close again)"
                STATE=WAIT_EXIT; EXIT_SEEN=0; DEB=0; LID_HOLD=0; PREV_DRV=$DRV; PREV_RL=$RL; PREV_RR=$RR
            fi
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
                    # ---- KEY-GATE: lock ONLY once the key has actually LEFT the cabin ----
                    # (KEY_GATE=0 -> this whole block is skipped, legacy blind-lock behavior.)
                    DO_LOCK=1
                    if [ "$KEY_GATE" = 1 ]; then
                        read_key_state; key_presence
                        KMSG=""
                        case "$KEY_P" in
                            GONE)
                                # Silence only means "it left" if the tag was heard AT the exit
                                # (within one debounce window of it). A tag already silent when
                                # you got out (dead battery, key not on you) proves nothing.
                                if [ -n "$EXIT_T" ] && [ "$KEY_SI" -ge $((EXIT_T - KEY_GONE_DEBOUNCE)) ]; then
                                    : # heard at exit, now gone -> the key LEFT -> proceed to lock
                                else
                                    DO_LOCK=0
                                    KMSG="key tag not heard at exit - not auto-locking"
                                    KLOG="key tag was already silent at the exit (last heard uptime $KEY_SI, exit $EXIT_T) — NOT locking (can't tell it left)"
                                fi
                                ;;
                            HERE)
                                DO_LOCK=0   # heard recently / not enough observed silence: hold
                                # Flash only for a key heard JUST NOW (within KEY_FLASH_FRESH):
                                # HERE also covers "heard 40 s ago, owner walking off" — that
                                # must not flash "key left inside" a few seconds before it locks.
                                if [ "$FLASHED" != 1 ] && [ "$WAITED" -ge "$FLASH_DELAY" ] &&
                                   [ -n "$KEY_AGE" ] && [ "$KEY_AGE" -le "$KEY_FLASH_FRESH" ]; then
                                    say "key STILL in the cabin after ${WAITED}s (heard ${KEY_AGE}s ago) — NOT locking (key-inside hold)"
                                    fire_hazard; FLASHED=1
                                fi
                                ;;
                            NOTAG)
                                DO_LOCK=0
                                KMSG="key tag not detected - not auto-locking"
                                KLOG="sensor alive but the key tag was never heard this boot — NOT locking (fail-safe)"
                                ;;
                            *)
                                DO_LOCK=0   # OFFLINE (board/reader down): can't confirm -> fail safe
                                KMSG="key sensor offline - not auto-locking"
                                KLOG="key sensor OFFLINE — NOT locking (fail-safe)  [seen=$KEY_SEEN beat=$KEY_BEAT boot=$KEY_BOOT]"
                                ;;
                        esac
                        if [ -n "$KMSG" ] && [ "$KEY_TOASTED" != 1 ]; then
                            say "$KLOG"; toast "$KMSG"; KEY_TOASTED=1
                        fi
                        # The hold is non-terminal (a key that leaves later still locks), but
                        # bounded: past KEY_HOLD_MAX after the exit, give up for this stop. A
                        # car kept awake for ages (charging, utility mode) must not get a
                        # late, rare RF gap's worth of "silence" to lock on.
                        if [ "$DO_LOCK" = 0 ] && [ -n "$EXIT_T" ] && [ -n "$NOW" ] &&
                           [ $((NOW - EXIT_T)) -ge "$KEY_HOLD_MAX" ]; then
                            say "key hold expired after $((NOW - EXIT_T))s (key-gate: $KEY_P) — NOT locking this stop. STATE=DONE"
                            STATE=DONE
                        fi
                    fi
                    if [ "$DO_LOCK" = 1 ]; then
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
                                say "      cause unknown. NOTE: this lock path has NO key-inside interlock"
                                say "      (tested), so a refusal is NOT evidence of a key inside."
                                say "      Leaving UNLOCKED. STATE=GAVE_UP"
                                STATE=GAVE_UP
                            else
                                # A refused fire only retries after a GENUINELY NEW exit.
                                say "fire $FIRES did not lock (lock=$LOCK) — need a fresh exit before retrying"
                                STATE=WAIT_EXIT; EXIT_SEEN=0; DEB=0; LID_HOLD=0; PREV_DRV=$DRV; PREV_RL=$RL; PREV_RR=$RR
                            fi
                        fi
                    fi
                    # DO_LOCK=0 (key held): stay ARMED and re-check every poll until
                    # KEY_HOLD_MAX — once the board has observed the debounce of silence, we lock.
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
