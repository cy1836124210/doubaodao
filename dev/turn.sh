#!/system/bin/sh
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze

echo "########## Simulate a REAL Doubao turn: start -> deltas -> end ##########"
am force-stop $APKG
content call --uri content://com.islandbridge.events --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null
echo "  app dead: pid=[$(pidof $APKG)]"

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

send '{"t":"chat.start","cid":"c9","cname":"测试会话","mid":"m9"}'
sleep 2
i=1
while [ $i -le 10 ]; do
  send "{\"t\":\"chat.delta\",\"cid\":\"c9\",\"mid\":\"m9\",\"kind\":\"text\",\"text\":\"流式片段$i \"}"
  i=$((i+1))
done
sleep 2
send '{"t":"chat.end","cid":"c9","mid":"m9"}'
sleep 6

echo "  app pid=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)]"
echo
echo "  --- delivery counts ---"
echo "    chat.start : $(logcat -d 2>/dev/null | grep -c 'ev ok chat.start')"
echo "    chat.delta : $(logcat -d 2>/dev/null | grep -c 'ev ok chat.delta')"
echo "    chat.end   : $(logcat -d 2>/dev/null | grep -c 'ev ok chat.end')"
echo
echo "  --- app log ---"
logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -12
echo
echo "  --- island pill (baseline 563..1030) ---"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
screencap -p /data/local/tmp/turn.png 2>/dev/null && echo "  screenshot saved"
