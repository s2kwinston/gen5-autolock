#!/system/bin/sh
###############################################################################
#  key-reader.sh — ESP32 BLE presence sensor -> /data/nemesis/key_state
#
#  Reads the dumb-sensor serial stream from the ESP32 on the HU's USB and keeps
#  a tiny state file the walk-away daemon polls. ALL policy (debounce, lock/flash
#  decisions) lives in walkaway.sh — this only reports "last heard / still alive".
#
#  Wire protocol (newline-terminated), one per scan window:
#     KEY 1 <rssi> <seq> [n]      the scan ran and heard the key (n = adverts heard)
#     KEY 0 0 <seq> [n]           the scan RAN and did not hear the key
#     ERR <reason> <ms> <seq>     the scan did NOT run properly (radio fault)
#  Only complete KEY lines count. ERR, partial and garbage lines are ignored and do NOT
#  refresh the beat — a board that can't prove it listened goes stale (fail safe).
#
#  State file (atomic replace), five lines:
#     seen_uptime=<float|->        /proc/uptime at the last KEY 1 (- = never this boot)
#     rssi=<int|->                 rssi of that last sighting
#     beat=<float>                 /proc/uptime at the last good KEY line
#     since=<float|->              start of the current CONTINUOUS feed: reset on every
#                                  tty open and after a gap > KEY_GAP between good lines
#     boot=<boot id>               this boot's kernel boot id (uptimes are per-boot)
#
#  How the daemon reads it (see walkaway.sh key_presence):
#     beat stale / file missing / other boot / garbled -> OFFLINE -> no lock
#     silence OBSERVED on one feed (beat - max(seen, since)) >= debounce -> GONE
#     otherwise -> HERE (hold). Silence the board wasn't there to hear never counts.
#  Every line is also appended to key_trace.log (the newest KEY_TRACE_MAX..2x lines of
#  this boot, so a long drive keeps its END, where the stop is), so the real in-car gaps
#  can be measured from the get-log stick.
#
#  WHICH tty: this head unit has BUILT-IN serial devices (ttyACM0/ttyACM1 and
#  ttyUSB0-2 exist before any board is plugged in). The reader must never open, stty
#  or read one of them. It only opens a /dev/ttyACM* whose USB device's vendor id is
#  in KEY_USB_VIDS (the key sensor), checked in sysfs before every open. Any other
#  node is skipped and logged once with its vendor id and product name.
#
#  Toolbox only: no printf/awk/grep/timeout. Same idioms as walkaway.sh.
###############################################################################
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 022
# (globbing is switched off only around the line split below: a serial "*" must not
# expand into filenames, but the /dev/ttyACM* and /sys scans need globbing)

# KEY_TTY unset (normal) = AUTO: pick the key sensor's node by USB vendor id.
# KEY_TTY set (bench / manual override) = read exactly that node or file.
KEY_TTY=${KEY_TTY:-}
KEY_DEVDIR=${KEY_DEVDIR:-/dev}
KEY_SYSTTY=${KEY_SYSTTY:-/sys/class/tty}
KEY_USB_VIDS=${KEY_USB_VIDS:-239a 303a}   # Adafruit's id (the tested key_scanner build reports it), Espressif
KEY_STATE=${KEY_STATE:-/data/nemesis/key_state}
KEY_UPTIME=${KEY_UPTIME:-/proc/uptime}
KEY_BOOTID_FILE=${KEY_BOOTID_FILE:-/proc/sys/kernel/random/boot_id}
KEY_BAUD=${KEY_BAUD:-115200}
KEY_LOG=${KEY_LOG:-/data/nemesis/gen5-autolock.log}   # shared with the daemon (append-only lines)
KEY_SYSUSB=${KEY_SYSUSB:-/sys/bus/usb}
KEY_CONF=${KEY_CONF:-/data/nemesis/gen5-autolock.conf}  # same config the daemon reads
KEY_GAP=${KEY_GAP:-8}         # s between good lines (windows are 2.5 s) that breaks the feed
KEY_TRACE=${KEY_TRACE:-/data/nemesis/key_trace.log}     # every line; the newest ones are kept
KEY_TRACE_MAX=${KEY_TRACE_MAX:-1500}                    # keep the last 1500-3000 lines: ~1-2 h, <= ~80 KB
# KEY_ONCE (bench): make one pass over the input then exit, instead of looping.

seen='-'
rssi='-'
since='-'     # uptime the current CONTINUOUS feed began (first good line after open / a gap)
lastok=''     # integer uptime of the previous good line
TRN=0
boot=''
read boot < "$KEY_BOOTID_FILE" 2>/dev/null

klog() { echo "$(date '+%Y-%m-%d %H:%M:%S') [key-reader] $*" >> "$KEY_LOG" 2>/dev/null; }

# ---- single instance ----------------------------------------------------------
# Exactly ONE reader per boot. Two readers would split the serial lines between them,
# each keeping its own "last seen" and overwriting the other's state — a present key
# could then read as gone. The lock lives in /data (survives reboot), so it records the
# boot id: a lock from a previous boot, or whose pid is dead, is stale and taken over.
KEY_LOCK=${KEY_LOCK:-/data/nemesis/key-reader.lock}
if ! mkdir "$KEY_LOCK" 2>/dev/null; then
    opid=""; oboot=""; read opid oboot < "$KEY_LOCK/owner" 2>/dev/null
    if [ -n "$opid" ] && [ "$opid" != "$$" ] && [ "$oboot" = "$boot" ] && [ -d "/proc/$opid" ]; then
        klog "another reader (pid $opid) is already running this boot — exiting"
        exit 0
    fi
    klog "taking over a stale lock (pid ${opid:-?}, boot ${oboot:-?})"
fi
echo "$$ $boot" > "$KEY_LOCK/owner"
release_lock() {
    o=""; read o _ < "$KEY_LOCK/owner" 2>/dev/null
    [ "$o" = "$$" ] && rm -rf "$KEY_LOCK" 2>/dev/null
}
trap release_lock EXIT
trap 'exit 0' INT TERM
# Unplugging the board hangs up the tty; if it became our controlling terminal that
# sends SIGHUP, which would kill the reader for the rest of the boot. Ignore it.
trap '' HUP

# The previous boot's file holds uptimes from a different clock: drop it before
# anything reads it (the daemon also rejects it by boot id; belt and braces).
# Only the lock holder gets here, so this never deletes a live reader's state.
rm -f "$KEY_STATE" "$KEY_STATE.tmp" 2>/dev/null
# The trace is ROTATED, not deleted: after a test the HU sleeps, and the boot that runs the
# get-log stick starts a new reader — the test drive's trace must still be there (.1).
# Keeps this boot + the 3 before it (each the last ~1-2 h of its boot).
mv "$KEY_TRACE.2" "$KEY_TRACE.3" 2>/dev/null
mv "$KEY_TRACE.1" "$KEY_TRACE.2" 2>/dev/null
mv "$KEY_TRACE"   "$KEY_TRACE.1" 2>/dev/null
rm -f "$KEY_TRACE.tmp" 2>/dev/null
trace() {
    echo "$*" >> "$KEY_TRACE" 2>/dev/null; TRN=$((TRN + 1))
    [ "$TRN" -ge $((KEY_TRACE_MAX * 2)) ] && trim_trace
}
# Keep only the newest KEY_TRACE_MAX lines (toolbox has no tail). Runs about once an hour
# and takes well under KEY_STALE; the board's lines wait in the tty buffer meanwhile.
# (trim_* names only: shell functions share globals, and the main loop uses t/ti/lastok)
trim_trace() {
    trim_skip=$((TRN - KEY_TRACE_MAX)); trim_n=0
    while IFS= read -r trim_line; do
        trim_n=$((trim_n + 1)); [ "$trim_n" -gt "$trim_skip" ] && echo "$trim_line"
    done < "$KEY_TRACE" > "$KEY_TRACE.tmp" 2>/dev/null
    if [ -s "$KEY_TRACE.tmp" ] && mv "$KEY_TRACE.tmp" "$KEY_TRACE" 2>/dev/null; then
        TRN=$KEY_TRACE_MAX
    else
        rm -f "$KEY_TRACE.tmp" 2>/dev/null; : > "$KEY_TRACE" 2>/dev/null; TRN=0   # can't trim: start over
    fi
}

# First-light diagnostics: can this kernel even make a /dev/ttyACM for the board?
if [ -d "$KEY_SYSUSB/drivers/cdc_acm" ]; then ACM=present; else ACM=ABSENT; fi
klog "starting: tty=${KEY_TTY:-auto (USB vendor $KEY_USB_VIDS)} state=$KEY_STATE boot=${boot:-none} cdc_acm-driver=$ACM"
# USB devices the kernel sees right now, as [vendor product] (the tested build shows as
# [239a QT Py ESP32-S3 ...], whatever the physical board)
usb_products() {
    pl=""
    for d in "$KEY_SYSUSB"/devices/*; do
        [ -f "$d/product" ] || continue
        p=""; v=""; read p < "$d/product" 2>/dev/null; read v < "$d/idVendor" 2>/dev/null
        [ -n "$p" ] && pl="$pl[$v $p]"
    done
    echo "${pl:-none}"
}
LASTUSB=""
WAITN=0
IDLE_SAID=0
SKIPPED=""

# AUTO mode: set PICK to the first /dev/ttyACM* whose USB device has a vendor id in
# KEY_USB_VIDS. The check reads sysfs only; a node that fails it is never opened. A node
# with no sysfs device (a leftover) or a foreign vendor (a built-in device) is skipped.
pick_tty() {
    PICK=""
    for t in "$KEY_DEVDIR"/ttyACM*; do
        [ -c "$t" ] || [ -f "$t" ] || continue
        n=${t##*/}; vid=""; prod=""
        if [ -e "$KEY_SYSTTY/$n/device" ]; then
            read vid < "$KEY_SYSTTY/$n/device/../idVendor" 2>/dev/null
            read prod < "$KEY_SYSTTY/$n/device/../product" 2>/dev/null
        fi
        if [ -n "$vid" ]; then
            case " $KEY_USB_VIDS " in *" $vid "*) PICK=$t; return 0 ;; esac
        fi
        case "$SKIPPED" in
            *"[$n:$vid]"*) ;;
            *) klog "skipping $t: USB vendor=${vid:-none} product=[$prod] is not the key sensor (never opened)"
               SKIPPED="$SKIPPED[$n:$vid]" ;;
        esac
    done
    return 1
}

# Is the key gate on? Parsed (never sourced) like the daemon: last KEY_GATE line wins,
# only an explicit 1 counts. Off = the package is installed without a board: stay idle.
gate_on() {
    g=0
    [ -f "$KEY_CONF" ] || return 1
    while read -r cl || [ -n "$cl" ]; do
        case "$cl" in KEY_GATE=*) v=${cl#KEY_GATE=}; g=${v%%[!0-9]*} ;; esac
    done < "$KEY_CONF"
    [ "$g" = 1 ]
}

now() { read u _ < "$KEY_UPTIME" 2>/dev/null; [ -n "$u" ] && echo "$u" || echo 0; }

# integer (optionally negative) — rejects '', 'x', 'KEY', partial fields
is_int() { case "$1" in ''|-|*[!0-9-]*) return 1 ;; *) return 0 ;; esac; }
# the LAST field may carry a trailing CR (Arduino println = CR LF, and a raw tty keeps
# the CR): accept anything that starts with a digit there.
is_seq() { case "$1" in [0-9]*) return 0 ;; *) return 1 ;; esac; }

write_state() { # [uptime of this line]
    b=${1:-$(now)}
    { echo "seen_uptime=$seen"; echo "rssi=$rssi"; echo "beat=$b"; echo "since=$since"; echo "boot=$boot"; } > "$KEY_STATE.tmp" 2>/dev/null
    mv "$KEY_STATE.tmp" "$KEY_STATE" 2>/dev/null
}

while :; do
    # Key gate off: do nothing (re-check every 30 s, so turning it on with the
    # settings stick takes effect without a reboot).
    if ! gate_on; then
        [ "$IDLE_SAID" = 1 ] || { klog "key gate off (KEY_GATE!=1 in $KEY_CONF) — idle"; IDLE_SAID=1; }
        [ -n "$KEY_ONCE" ] && break
        sleep 30; continue
    fi
    [ "$IDLE_SAID" = 1 ] && { klog "key gate on — watching for the board"; IDLE_SAID=0; }
    # Resolve the board's serial node afresh on every (re)connect: its number depends on
    # what else holds ttyACM minors (built-in devices do), and it can change after the
    # one shared USB port was used for a stick.
    if [ -n "$KEY_TTY" ]; then TTY=$KEY_TTY; else TTY=""; pick_tty && TTY=$PICK; fi
    # Wait for the device to exist. While it is gone, beat does not advance,
    # so the daemon reads OFFLINE and fails safe (does not lock).
    if [ -z "$TTY" ] || { [ ! -c "$TTY" ] && [ ! -f "$TTY" ]; }; then
        # every ~30 s, log what USB devices the kernel sees if that changed: tells a
        # missing driver (board listed, no ttyACM) from a dead cable/port (not listed)
        if [ $((WAITN % 15)) = 0 ]; then
            U=$(usb_products)
            [ "$U" != "$LASTUSB" ] && { klog "waiting for the board: no key-sensor tty yet (USB vendor $KEY_USB_VIDS); USB devices: $U (cdc_acm-driver=$ACM)"; LASTUSB=$U; }
        fi
        WAITN=$((WAITN + 1))
        [ -n "$KEY_ONCE" ] && break
        sleep 2; continue
    fi
    # Raw, no echo: a CDC tty left in canonical+ECHO loops the board's output back
    # into its input. stty may be absent on this toolbox (then the tty stays in its
    # cooked default: lines still arrive whole, and the firmware drains any echo).
    if stty -F "$TTY" raw -echo "$KEY_BAUD" 2>/dev/null; then TTYMODE=raw; else TTYMODE=cooked; fi
    klog "board connected: $TTY (tty mode $TTYMODE)"
    LASTUSB=""; FIRST=1
    since='-'; lastok=''          # a new open starts a new feed: silence before it is unobserved
    trace "$(now) # connected $TTY"

    while read line; do
        t=$(now); ti=${t%%.*}
        [ "$FIRST" = 1 ] && case "$line" in KEY*|ERR*) klog "first data line from the board: ${line%%[!A-Za-z0-9 -]*}"; FIRST=0 ;; esac
        set -f; set -- $line; set +f
        trace "$t $*"
        # Only a COMPLETE `KEY <0|1> <int> <seq> [n]` line is evidence. KEY 1 = heard; KEY 0 =
        # the scan RAN and did not hear it (the firmware prints ERR, not KEY 0, when a scan
        # fails). Anything else — ERR, partial, garbage — is ignored and does NOT advance the
        # beat, so a deaf or babbling board goes stale -> OFFLINE -> no lock.
        ok=0
        if [ "$1" = KEY ] && is_int "$3" && is_seq "$4"; then
            case "$2" in
                1) rssi="$3"; seen=$t; ok=1 ;;
                0) ok=1 ;;
            esac
        fi
        if [ "$ok" = 1 ]; then
            # A feed is continuous while good lines keep coming; a gap (lost lines, a
            # board reset) starts a new one. The daemon only counts silence since `since`.
            if [ "$since" = - ] || [ -z "$lastok" ] || [ $((ti - lastok)) -gt "$KEY_GAP" ]; then
                since=$t
            fi
            lastok=$ti
            write_state "$t"
        fi
    done < "$TTY"

    # EOF/closed (device unplugged, or bench input exhausted)
    trace "$(now) # disconnected"
    klog "board disconnected: $TTY (seen=$seen)"
    [ -n "$KEY_ONCE" ] && break
    sleep 1
done
