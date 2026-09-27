#!/system/bin/sh
APKG=com.islandbridge
URI=content://com.islandbridge.events
CACHE=/data/user_de/0/com.android.systemui/cache

echo "########## 1. Where does the island keep live card state? ##########"
ls -l $CACHE/*.sqlite* 2>/dev/null
echo "  --- files dir ---"
ls -l /data/user_de/0/com.android.systemui/files/ 2>/dev/null | head -20

echo
echo "########## 2. Send a card with a UNIQUE marker ##########"
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null
MARK="ZQMARK$(date +%H%M%S)"
EV="{\"t\":\"plan.start\",\"tid\":\"$MARK\",\"title\":\"$MARK 进度测试\",\"total\":0}"
content call --uri $URI --method event --extra evb:s:"$(echo -n "$EV" | base64 -w0)"
sleep 6
echo "  marker = $MARK"

echo
echo "########## 3. Does the marker appear anywhere island-side? ##########"
for f in $CACHE/*.sqlite; do
  if grep -q "$MARK" "$f" 2>/dev/null; then echo "  FOUND in $f"; fi
done
grep -rl "$MARK" /data/user_de/0/com.android.systemui/ 2>/dev/null | head -5
echo "  --- did our app log the push? ---"
logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -12

echo
echo "########## 4. Island window / view present? ##########"
dumpsys window 2>/dev/null | grep -iE "astraflow|island" | head -10
echo "  --- island threads active ---"
dumpsys activity service com.android.systemui 2>/dev/null | grep -icE "AstraIsland"

echo
echo "########## 5. screenshot ##########"
screencap -p /data/local/tmp/card3.png 2>/dev/null && echo "  captured (marker $MARK)"
