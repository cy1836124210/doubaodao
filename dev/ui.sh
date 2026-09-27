#!/system/bin/sh
# Read what text the island actually holds in its view tree + its own DB.
APKG=com.islandbridge
URI=content://com.islandbridge.events
SQ=/data/user_de/0/com.android.systemui/files/astraflow_sqlite3

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

send '{"t":"chat.start","cid":"cU","cname":"UIA","mid":"mU"}'
sleep 5
echo "### sending marker-bearing deltas ###"
send '{"t":"chat.delta","cid":"cU","mid":"mU","kind":"text","text":"ZZHEADZZ "}'
sleep 1
i=1
while [ $i -le 6 ]; do
  send "{\"t\":\"chat.delta\",\"cid\":\"cU\",\"mid\":\"mU\",\"kind\":\"text\",\"text\":\"ZTAIL$i \"}"
  i=$((i+1))
done
sleep 4

echo
echo "### what is in the island's DB events table? ###"
DB=/data/user_de/0/com.android.systemui/cache/astraflow-island-message-history.sqlite
$SQ "$DB" "select name from sqlite_master where type='table';" 2>&1 | head
echo "  -- columns --"
$SQ "$DB" "pragma table_info(events);" 2>&1 | head -20
echo "  -- newest rows (grep our markers) --"
$SQ "$DB" "select * from events order by rowid desc limit 6;" 2>&1 | grep -oE 'ZZHEADZZ[^"]*|ZTAIL[0-9 ]*' | head -10
$SQ "$DB" "select * from events order by rowid desc limit 6;" 2>&1 | tail -8

echo
echo "### a11y tree: grep for our markers ###"
uiautomator dump /data/local/tmp/ui2.xml >/dev/null 2>&1
echo "  ZZHEADZZ present in UI tree? : $(grep -c 'ZZHEADZZ' /data/local/tmp/ui2.xml 2>/dev/null)"
echo "  ZTAIL6   present in UI tree? : $(grep -c 'ZTAIL6' /data/local/tmp/ui2.xml 2>/dev/null)"
echo "  -- the actual island node text --"
tr '>' '>\n' < /data/local/tmp/ui2.xml 2>/dev/null | grep -oE 'text="[^"]*"' | grep -E 'ZZHEAD|ZTAIL' | head -5
echo "  -- any node from com.android.systemui --"
tr '>' '>\n' < /data/local/tmp/ui2.xml 2>/dev/null | grep -E 'com.android.systemui|AstraIsland' | head -5
