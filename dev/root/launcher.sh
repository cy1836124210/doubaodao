#!/system/bin/sh
# IslandBridge root launcher — the ONLY .sh in /data/adb/service.d.
#
# KernelSU runs every executable .sh it finds in service.d, so the actual
# workers live in /data/adb/islandbridge/ and are started from here. This
# script is idempotent: it is invoked at boot by KernelSU and again by the app
# (BridgeService) whenever the bridge service starts, and will not create
# duplicate workers.
#
# Workers:
#   relay.sh  — drains the Doubao hook's event queue into the app over Binder
#   listen.sh — LAN listener (configurable IP/port) feeding the same channel
#
# Usage: islandbridge.sh [restart]
#   restart — force-kill and respawn both workers (used after a config change)

DIR=/data/adb/islandbridge
LOG=/data/local/tmp/islandbridge_relay.log

# KernelSU service.d runs with a minimal PATH that has no coreutils/busybox
# (observed: "/system/bin/sleep: No such file or directory" -> both workers
# spun in a tight error loop). Bring in the KernelSU busybox explicitly.
export PATH=/data/adb/ksu/bin:/system/bin:/system/xbin:$PATH
BB=/data/adb/ksu/bin/busybox
[ -x "$BB" ] || BB=

# service.d fires very early in boot, before /data/data/<pkg> exists (CE
# storage is still locked). Starting workers then makes them fail on their
# pid/queue files, so wait for boot to finish and for the package dirs.
wait_ready() {
    i=0
    while [ $i -lt 180 ]; do
        if [ "$(getprop sys.boot_completed)" = "1" ] &&
           [ -d /data/data/com.islandbridge ] &&
           [ -d /data/data/com.larus.nova ]; then
            return 0
        fi
        sleep 2
        i=$((i+1))
    done
    echo "$(date) wait_ready timed out; starting anyway" >> "$LOG" 2>/dev/null
    return 0
}

alive() { [ -d "/proc/$1" ] 2>/dev/null; }

pidof_script() {
    # matches on the script path in /proc/*/cmdline (pgrep self-matches)
    for d in /proc/[0-9]*; do
        c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
        case "$c" in *"$1"*) echo "${d#/proc/}"; return 0 ;; esac
    done
    return 1
}

spawn() {
    name=$1
    p=$(pidof_script "$DIR/$name.sh")
    if [ -n "$p" ]; then
        echo "$(date) $name already running pid=$p" >> "$LOG" 2>/dev/null
        return 0
    fi
    if [ -n "$BB" ]; then
        setsid "$BB" sh "$DIR/$name.sh" </dev/null >> "$LOG" 2>&1 &
    else
        setsid sh "$DIR/$name.sh" </dev/null >> "$LOG" 2>&1 &
    fi
    echo "$(date) $name spawned pid=$!" >> "$LOG" 2>/dev/null
}

case "$1" in
    restart)
        for n in relay listen; do
            p=$(pidof_script "$DIR/$n.sh")
            [ -n "$p" ] && kill -9 "$p" 2>/dev/null
        done
        sleep 1
        ;;
esac

[ -d "$DIR" ] || exit 0
[ "$1" = "restart" ] || wait_ready

# Serialise concurrent invocations: service.d fires this at boot while the
# app's BridgeService may call it at the same moment, and two runs racing
# between "no process found" and "setsid" would double-spawn the workers.
# mkdir is atomic, so it doubles as a lock; a stale lock is broken by age.
LOCK=/data/adb/islandbridge/.lock
i=0
while ! mkdir "$LOCK" 2>/dev/null; do
    # break a lock older than 30s (previous run died mid-spawn)
    if [ -d "$LOCK" ]; then
        age=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
        [ "$age" -gt 30 ] && rm -rf "$LOCK" 2>/dev/null && continue
    fi
    i=$((i+1))
    [ $i -gt 15 ] && { echo "$(date) lock busy, skipping" >> "$LOG" 2>/dev/null; exit 0; }
    sleep 1
done
trap 'rm -rf "$LOCK" 2>/dev/null' EXIT

spawn relay
spawn listen
