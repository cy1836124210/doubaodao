#!/system/bin/sh
APKG=com.islandbridge
URI=content://com.islandbridge.events
SQ=/data/user_de/0/com.android.systemui/files/astraflow_sqlite3
DB=/data/user_de/0/com.android.systemui/cache/astraflow-island-message-history.sqlite

echo "########## 1. Island DB schema (their own sqlite3) ##########"
$SQ "$DB" ".tables" 2>&1 | head
echo "  --- any table with our marker? ---"

am force-stop $APKG; sleep 2
logcat -c 2>/dev/null
MARK="ZQ$(date +%H%M%S)"
EV="{\"t\":\"plan.start\",\"tid\":\"$MARK\",\"title\":\"$MARK 豆包在忙\",\"total\":0}"
content call --uri $URI --method event --extra evb:s:"$(echo -n "$EV" | base64 -w0)" >/dev/null
sleep 6
echo "  marker = $MARK"

for t in $($SQ "$DB" ".tables" 2>/dev/null); do
  echo "  --- table $t ---"
  $SQ "$DB" "select * from $t limit 5;" 2>&1 | head -12
done

echo
echo "########## 2. Live activities via island's own dumpsys surface ##########"
dumpsys activity service com.android.systemui 2>/dev/null | grep -iE "AstraIsland-" | head -12

echo
echo "########## 3. Proof-by-geometry: touchableRegion scales with title length ##########"
probe(){
  EV="{\"t\":\"plan.start\",\"tid\":\"g\",\"title\":\"$1\",\"total\":0}"
  content call --uri $URI --method event --extra evb:s:"$(echo -n "$EV" | base64 -w0)" >/dev/null
  sleep 3
  echo "   title='$1' -> $(dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1 | grep -o 'SkRegion([^)]*)')"
}
probe "短"
probe "这是一个相当长的标题用来撑开岛的宽度"
