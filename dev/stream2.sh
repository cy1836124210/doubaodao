#!/system/bin/sh
# Empirically determine WHY only the head of the stream is visible.
# Theory: the compact info area marquee-scrolls a long body, and every
# update restarts the scroll at position 0 — so the newest text (at the
# END of the string) never reaches the screen.
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
URI=content://com.islandbridge.events

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

echo "### start a reply card ###"
send '{"t":"chat.start","cid":"cL","cname":"长文测试","mid":"mL"}'
sleep 6
echo "  app pid=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)]"

echo
echo "### stream 10 segments, each marked with its index ###"
i=1
while [ $i -le 10 ]; do
  send "{\"t\":\"chat.delta\",\"cid\":\"cL\",\"mid\":\"mL\",\"kind\":\"text\",\"text\":\"段$i内容。\"}"
  # screenshot AFTER segment 4 and AFTER segment 10, long after the 300ms throttle
  case $i in
    4)  sleep 3; screencap -p /data/local/tmp/s4.png ;;
    10) sleep 3; screencap -p /data/local/tmp/s10.png ;;
  esac
  i=$((i+1))
done
sleep 3
screencap -p /data/local/tmp/s11.png

echo
echo "### did the displayed text change between segment 4 and 10? ###"
echo "  (0 differing pixels => the card is NOT following the stream)"
echo "  s4 vs s10/crop-pill:"
screencap -p /data/local/tmp/now.png

echo
echo "### what did the app actually send to the island? ###"
logcat -d 2>/dev/null | grep -E "IslandBridge" | grep -E "chat.delta|pushReply|body" | tail -6

echo
echo "### app-side accumulated reply buffer length (via log of last body) ###"
logcat -d 2>/dev/null | grep -c "ev ok chat.delta"

echo
echo "### pill geometry ###"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1

echo
echo "### what the island STORED as the body (its own history db) ###"
SQ=/data/user_de/0/com.android.systemui/files/astraflow_sqlite3
DB=/data/user_de/0/com.android.systemui/cache/astraflow-island-message-history.sqlite
ls -l $DB 2>/dev/null
$SQ "$DB" "select id, length(text) from message_history order by rowid desc limit 3;" 2>&1 | head -10
