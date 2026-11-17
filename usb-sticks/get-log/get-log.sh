#!/system/bin/sh
# gen5-autolock — GET LOG stick.
# READ-ONLY: copies the daemon's log, its config, a one-shot body-control
# snapshot and key-sensor USB diagnostics (USB devices, serial nodes, dmesg,
# logcat) onto THIS USB stick, so you can read them on a computer. It changes
# NOTHING on the car and never locks or unlocks. The snapshot is a cache read
# (dumpsys) and sends no CAN. Toolbox/mksh only — no printf.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
umask 022

SELF=${0%/*}
ND=/data/nemesis
LOG=${GEN5_LOG:-$ND/gen5-autolock.log}
CONF=${GEN5_CONF:-$ND/gen5-autolock.conf}

STAMP=$(date '+%Y%m%d-%H%M%S' 2>/dev/null)
[ -n "$STAMP" ] || STAMP=snapshot
DEST="$SELF/gen5-autolock-logs/$STAMP"

say() { echo "$*"; echo "$(date '+%Y-%m-%d %H:%M:%S') [get-log] $*" >> "$LOG" 2>/dev/null; }

mkdir -p "$DEST" 2>/dev/null || { say "ERROR: cannot write to the USB stick. Nothing copied."; exit 1; }

# Copy BEFORE we log our own notes, so the pulled log reflects the daemon only.
cp "$LOG"  "$DEST/gen5-autolock.log"  2>/dev/null
cp "$CONF" "$DEST/gen5-autolock.conf" 2>/dev/null
cp -r "$ND/logs/gen5.autolock" "$DEST/service-log" 2>/dev/null
# key sensor (KEY_GATE=1 only; absent otherwise): last state + the boot id it belongs to
cp "$ND/key_state" "$DEST/key_state.txt" 2>/dev/null
# every sensor line (first ~1 h per boot): this boot's and the 3 boots before it — the
# test drive is usually .1, because plugging in this stick happens on a later boot
for tf in "$ND"/key_trace.log*; do [ -f "$tf" ] && cp "$tf" "$DEST/" 2>/dev/null; done
cat /proc/sys/kernel/random/boot_id > "$DEST/boot_id.txt" 2>/dev/null
ls -l /dev/ttyACM* > "$DEST/tty.txt" 2>&1
# Body-control snapshot: a CACHE read, sends NO CAN. Open the liftgate/doors
# first to capture them here (e.g. "mTrunkOpenedState: 1").
dumpsys com.hkmc.micom.bcm > "$DEST/bcm-snapshot.txt" 2>&1

# Key-sensor USB diagnostics (read-only): which USB devices the kernel sees, which
# driver each interface bound to, which USB device owns each /dev/ttyACM* / ttyUSB*
# node (a node with no class link is a leftover), and which process holds each one open.
{
    echo "== /dev serial nodes"
    ls -l /dev/ttyACM* /dev/ttyUSB* 2>&1
    echo "== /proc/tty/drivers"
    cat /proc/tty/drivers 2>&1
    echo "== tty nodes -> owning USB device"
    for t in /sys/class/tty/ttyACM* /sys/class/tty/ttyUSB*; do
        [ -e "$t" ] || continue
        echo "-- ${t##*/}"
        ls -l "$t" 2>&1
        ls -l "$t/device" 2>&1
        for f in idVendor idProduct manufacturer product; do
            v=""; read v < "$t/device/../$f" 2>/dev/null
            echo "   $f=$v"
        done
    done
    echo "== USB devices"
    for d in /sys/bus/usb/devices/*; do
        [ -f "$d/idVendor" ] || continue
        vid=""; pid=""; pr=""; mf=""
        read vid < "$d/idVendor" 2>/dev/null; read pid < "$d/idProduct" 2>/dev/null
        read pr < "$d/product" 2>/dev/null; read mf < "$d/manufacturer" 2>/dev/null
        echo "${d##*/} vid=$vid pid=$pid manufacturer=[$mf] product=[$pr]"
    done
    echo "== USB interfaces -> bound driver"
    for i in /sys/bus/usb/devices/*:*; do
        [ -d "$i" ] || continue
        c=""; read c < "$i/bInterfaceClass" 2>/dev/null
        drv="(none)"; [ -e "$i/driver" ] && drv=$(ls -l "$i/driver" 2>&1)
        echo "${i##*/} class=$c driver: $drv"
    done
    echo "== processes holding a serial node open"
    for p in /proc/[0-9]*; do
        ls -l "$p/fd" 2>/dev/null | while read -r fl; do
            case "$fl" in
                *ttyACM*|*ttyUSB*) c=""; read c < "$p/comm" 2>/dev/null; echo "pid ${p##*/} ($c): $fl" ;;
            esac
        done
    done
    echo "== ps"
    ps 2>&1
} > "$DEST/usb-diag.txt" 2>&1
dmesg > "$DEST/dmesg.txt" 2>&1
logcat -d -v time > "$DEST/logcat.txt" 2>&1

say "Copied log + config + a body-control snapshot to: gen5-autolock-logs/$STAMP/ on the USB."
say "Done — remove the stick and open that folder on a computer."
exit 0
