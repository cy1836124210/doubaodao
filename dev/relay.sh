#!/system/bin/sh
echo "########## 1. Is the boot-time root relay actually running? ##########"
echo "  service.d script:"; ls -l /data/adb/service.d/islandbridge.sh 2>/dev/null
echo "  processes:"; ps -A -o PID,PPID,ARGS 2>/dev/null | grep -E "islandbridge.sh|ib_relay" | grep -v grep
echo "  pidfile: [$(cat /data/data/com.islandbridge/files/ib_relay.pid 2>/dev/null)]"

echo
echo "########## 2. Trace the relay path end to end ##########"
echo "  queue file (written by the Doubao hook):"
ls -l /data/data/com.larus.nova/files/ibq.log* 2>/dev/null || echo "    (none yet)"
echo "  app-local relay script transport:"
grep -c "content call" /data/data/com.islandbridge/files/ib_relay.sh 2>/dev/null
echo "  boot script transport:"
grep -c "content call" /data/adb/service.d/islandbridge.sh 2>/dev/null

echo
echo "########## 3. Simulate a Doubao capture landing in the queue ##########"
API=com.islandbridge; APKG=$API
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null
echo "  app killed: pid=[$(pidof $APKG)]"
# the hook appends base64 lines here; the relay should pick it up
EV='{"t":"plan.start","tid":"relaytest","title":"ROOT RELAY TEST","total":0}'
echo -n "$EV" | base64 -w0 > /data/data/com.larus.nova/files/ibq.log
chown 10375:10375 /data/data/com.larus.nova/files/ibq.log 2>/dev/null
echo "  wrote event to ibq.log"
sleep 6
echo "  app pid after: [$(pidof $APKG)]"
echo "  --- app log ---"
logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -8
echo "  --- island geometry ---"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
