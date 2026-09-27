#!/system/bin/sh
APKG=com.islandbridge
URI=content://com.islandbridge.events
CONF=/data/data/com.islandbridge/files/ib_listen.conf

echo "########## 1. Workers alive (single instance each)? ##########"
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/relay*|*islandbridge/listen*) echo "  $p: $c" ;; esac
done
echo "  relay pidfile : [$(cat /data/data/com.islandbridge/files/ib_relay.pid 2>/dev/null)]"
echo "  listen pidfile: [$(cat /data/data/com.islandbridge/files/ib_listen.pid 2>/dev/null)]"

echo
echo "########## 2. Configure the listener with a token ##########"
cat > $CONF <<EOF
BIND=0.0.0.0
PORT=8799
TOKEN=zqtok123
EOF
chown 10370:10370 $CONF 2>/dev/null
chmod 600 $CONF
cat $CONF
sh /data/adb/service.d/islandbridge.sh restart
sleep 3

echo
echo "########## 3. Reject a bad token, accept a good one ##########"
am force-stop $APKG; sleep 3
logcat -c 2>/dev/null
echo "  app killed: pid=[$(pidof $APKG)]"
echo "  -- wrong token --"
printf 'WRONGTOKEN\t{"t":"plan.start","tid":"z","title":"SHOULD NOT APPEAR"}\n' | nc 127.0.0.1 8799
sleep 2
echo "  -- correct token --"
printf 'zqtok123\t{"t":"plan.start","tid":"good","title":"TCP+TOKEN OK","total":0}\n' | nc 127.0.0.1 8799
sleep 5
echo "  app pid: [$(pidof $APKG)]"
echo "  --- relay log ---"; tail -8 /data/local/tmp/islandbridge_relay.log
echo "  --- app log ---"; logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -6
echo "  --- island geometry (should be wider than baseline 563-1030) ---"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
