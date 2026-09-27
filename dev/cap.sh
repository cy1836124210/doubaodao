#!/system/bin/sh
APKG=com.islandbridge
OUT=/data/local/tmp/cap.log
URI=content://com.islandbridge.events

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2

# capture the WHOLE app pipeline to a file, so nothing depends on the ring buffer
logcat -c 2>/dev/null
logcat -v time -s IslandBridge:* > $OUT 2>&1 &
LP=$!
sleep 2
echo "app dead: pid=[$(pidof $APKG)]"

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }
send '{"t":"chat.start","cid":"cX","cname":"会话X","mid":"mX"}'
sleep 2
send '{"t":"chat.delta","cid":"cX","mid":"mX","kind":"text","text":"片段A "}'
sleep 1
send '{"t":"chat.delta","cid":"cX","mid":"mX","kind":"text","text":"片段B "}'
sleep 1
send '{"t":"chat.end","cid":"cX","mid":"mX"}'
sleep 5
kill -9 $LP 2>/dev/null
sleep 1

echo
echo "===== captured app log ====="
cat $OUT
echo
echo "===== counts ====="
echo "  chat.start: $(grep -c 'chat.start' $OUT)"
echo "  chat.delta: $(grep -c 'chat.delta' $OUT)"
echo "  chat.end  : $(grep -c 'chat.end' $OUT)"
echo
echo "  pill: $(dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1)"
