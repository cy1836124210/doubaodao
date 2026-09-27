#!/system/bin/sh
# IslandBridge root event relay + freeze-aware delivery (prototype v2).
# ColorOS freezes the whole app cgroup (cgroup.freeze=1), which makes
# BroadcastQueue defer our events until the user foregrounds the app.
# We run as root, so thaw the app's cgroup right before delivering.
F=/data/data/com.larus.nova/files/ibq.log
P=$F.proc
PIDFILE=/data/data/com.islandbridge/files/ib_relay.pid
LOG=/data/local/tmp/relay2.log
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze

echo $$ > "$PIDFILE" 2>/dev/null
: > "$F" 2>/dev/null
echo "=== relay2 start $(date) ===" > $LOG

thaw() {
    [ -f "$CF" ] || return 0
    if [ "$(cat $CF 2>/dev/null)" = "1" ]; then
        echo 0 > "$CF" 2>/dev/null && echo "THAW $(date +%H:%M:%S)" >> $LOG
    fi
}

while true; do
    if [ -s "$F" ]; then
        mv "$F" "$P" 2>/dev/null
        thaw
        n=0
        while IFS= read -r b64; do
            [ -z "$b64" ] && continue
            am broadcast -a com.islandbridge.EVENT \
                -n com.islandbridge/.BridgeEventReceiver \
                --ei v 2 --es evb "$b64" >/dev/null 2>&1
            n=$((n+1))
            thaw
        done < "$P" 2>/dev/null
        echo "relayed=$n freeze_now=$(cat $CF 2>/dev/null) $(date +%H:%M:%S)" >> $LOG
        rm -f "$P" 2>/dev/null
    fi
    sleep 1
done
