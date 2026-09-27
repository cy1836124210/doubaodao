#!/system/bin/sh
echo "########## 1. Consolidate: remove the duplicate standalone relay ##########"
rm -f /data/adb/service.d/islandbridge.sh
ls -l /data/adb/service.d/
echo "  (zz_islandbridge.sh is now the ONLY spawner)"

echo
echo "########## 2. Is the relay loop alive? full cmdline scan ##########"
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *relay*|*listen*) echo "  $p: $c" ;; esac
done

echo
echo "########## 3. THE IP FEATURE: inject an event over TCP, app killed ##########"
APKG=com.islandbridge
URI=content://com.islandbridge.events
am force-stop $APKG; sleep 3
logcat -c 2>/dev/null
echo "  app killed: pid=[$(pidof $APKG)]"

# what port is the listener on?
PORT=$(cat /data/data/com.islandbridge/files/ib_listen.port 2>/dev/null)
[ -z "$PORT" ] && PORT=8799
echo "  listener port = $PORT"

# inject from the device itself (simulating a LAN client) — newline framed
EV='{"t":"plan.start","tid":"tcp1","title":"TCP注入的卡片","total":0}'
echo "$EV" | nc 127.0.0.1 $PORT
sleep 6
echo "  app pid after: [$(pidof $APKG)]"
echo "  --- relay log ---"
tail -6 /data/local/tmp/islandbridge_relay.log 2>/dev/null
echo "  --- app log ---"
logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -8
echo "  --- island geometry ---"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
