#!/system/bin/sh
# DECISIVE: which part of the string does the island render — head or tail?
# Send HEADTOKEN, then 60 filler chars to force overflow, then TAILTOKEN.
# Background Doubao (HOME) so SystemUI is the focused window, then read the
# accessibility tree and look for which token is present.
APKG=com.islandbridge
URI=content://com.islandbridge.events

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

send '{"t":"chat.start","cid":"cT","cname":"HT","mid":"mT"}'
sleep 5
send '{"t":"chat.delta","cid":"cT","mid":"mT","kind":"text","text":"HEADTOKEN "}'
sleep 1
F=""
i=1
while [ $i -le 60 ]; do F="$F字"; i=$((i+1)); done
send "{\"t\":\"chat.delta\",\"cid\":\"cT\",\"mid\":\"mT\",\"kind\":\"text\",\"text\":\"$F\"}"
sleep 1
send '{"t":"chat.delta","cid":"cT","mid":"mT","kind":"text","text":" TAILTOKEN"}'
sleep 3

echo "### app received: head + 60 filler + tail ###"
echo
echo "### background Doubao so SystemUI is focused ###"
input keyevent KEYCODE_HOME
sleep 3
dumpsys window 2>/dev/null | grep mCurrentFocus

echo
echo "### dump the accessibility tree ###"
uiautomator dump /data/local/tmp/ht.xml >/dev/null 2>&1
echo "  dump bytes: $(wc -c < /data/local/tmp/ht.xml 2>/dev/null)"
echo "  HEADTOKEN found : $(grep -c 'HEADTOKEN' /data/local/tmp/ht.xml 2>/dev/null)"
echo "  TAILTOKEN found : $(grep -c 'TAILTOKEN' /data/local/tmp/ht.xml 2>/dev/null)"
echo
echo "  --- every non-empty text node in the tree ---"
tr '>' '>\n' < /data/local/tmp/ht.xml 2>/dev/null | grep -oE 'text="[^"]*"' | grep -v 'text=""' | head -20
echo
echo "  --- the long filler node, as rendered (first 200 chars) ---"
tr '>' '>\n' < /data/local/tmp/ht.xml 2>/dev/null | grep -oE 'text="[^"]{40,}"' | head -2 | cut -c1-200
echo
echo "### pill width ###"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
