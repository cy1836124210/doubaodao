#!/system/bin/sh
APKG=com.islandbridge
CONF=/data/data/com.islandbridge/files/ib_listen.conf
PORT=8799

echo "########## A. token rejection / acceptance (app KILLED) ##########"
cat $CONF
am force-stop $APKG; sleep 3
logcat -c 2>/dev/null
echo "  app killed: pid=[$(pidof $APKG)]"

echo "  -- wrong token (must be dropped) --"
printf 'BADTOKEN\t{"t":"plan.start","tid":"bad","title":"SHOULD NOT APPEAR"}\n' | nc 127.0.0.1 $PORT
sleep 3
echo "  -- correct token (must pass) --"
printf 'zqtok123\t{"t":"plan.start","tid":"good","title":"TCP TOKEN OK","total":0}\n' | nc 127.0.0.1 $PORT
sleep 6
echo "  app pid : [$(pidof $APKG)]"
echo "  --- relay log ---"; tail -6 /data/local/tmp/islandbridge_relay.log
echo "  --- app log ---"; logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -8
echo "  --- island pill width (baseline is 563..1030 = 467px) ---"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1

echo
echo "########## B. plain JSON with NO token prefix should now be dropped ##########"
printf '{"t":"plan.start","tid":"notok","title":"NO TOKEN"}\n' | nc 127.0.0.1 $PORT
sleep 3
tail -3 /data/local/tmp/islandbridge_relay.log

echo
echo "########## C. restart hygiene: does a stale nc hold the port? ##########"
sh /data/adb/service.d/islandbridge.sh restart
sleep 3
netstat -tlnp 2>/dev/null | grep ":$PORT"
