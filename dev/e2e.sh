#!/system/bin/sh
APKG=com.islandbridge
AUID=10370
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze
st(){ echo "     pid=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)]"; }

echo "########## 0. root relay service state ##########"
echo "  service.d script: $(ls -l /data/adb/service.d/islandbridge.sh 2>/dev/null | head -1)"
echo "  running relays:"
ps -A -o PID,ARGS 2>/dev/null | grep -E "ib_relay|islandbridge.sh" | grep -v grep
echo "  pidfile: $(cat /data/data/com.islandbridge/files/ib_relay.pid 2>/dev/null)"
echo "  cached app script first line: $(head -3 /data/data/com.islandbridge/files/ib_relay.sh 2>/dev/null | tr '\n' ' ')"

echo
echo "########## 1. KILL the app completely ##########"
am force-stop $APKG; sleep 3
st
echo "  provider record now: $(dumpsys activity providers 2>/dev/null | grep -c com.islandbridge.events)"

echo
echo "########## 2. THE TEST: binder event into a DEAD app ##########"
EV='{"t":"plan.start","tid":"e2e-test","title":"E2E BINDER TEST","total":3}'
B64=$(echo -n "$EV" | base64 -w0)
logcat -c 2>/dev/null
echo "  calling provider (app is dead)..."
content call --uri content://com.islandbridge.events --method event --extra evb:s:"$B64"
sleep 6
st
echo "  --- app log ---"
logcat -d 2>/dev/null | grep -iE "IslandBridge|island" | tail -15

echo
echo "########## 3. Did it reach the island? ##########"
logcat -d 2>/dev/null | grep -iE "astraisland|astraflow|island.*start|onSessionReady" | tail -12
