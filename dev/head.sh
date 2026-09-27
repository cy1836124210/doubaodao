#!/system/bin/sh
# DECISIVE TEST: is the island rendering the HEAD or the TAIL of the string?
#
# Send a reply whose head is a fixed 20-char prefix "HEADxxxxxxxxxxxxxxxx"
# and whose tail grows one digit per frame:
#     HEADxxxxxxxxxxxxxxxx1
#     HEADxxxxxxxxxxxxxxxx12
#     HEADxxxxxxxxxxxxxxxx123   ...
# If the card shows the HEAD, the visible pixels freeze as soon as the text
# overflows. If it shows the TAIL, they keep changing.
APKG=com.islandbridge
URI=content://com.islandbridge.events

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

send '{"t":"chat.start","cid":"cD","cname":"诊断","mid":"mD"}'
sleep 6
echo "  card up: pid=[$(pidof $APKG)]"

# constant 20-char head
send '{"t":"chat.delta","cid":"cD","mid":"mD","kind":"text","text":"HEADHEADHEADHEADHEAD"}'
sleep 3
screencap -p /data/local/tmp/h0.png
echo "  sent constant head"

i=1
while [ $i -le 9 ]; do
  send "{\"t\":\"chat.delta\",\"cid\":\"cD\",\"mid\":\"mD\",\"kind\":\"text\",\"text\":\"$i\"}"
  i=$((i+1))
done
sleep 4
screencap -p /data/local/tmp/h9.png
echo "  sent 9 growing tail digits"
echo
echo "  pill: $(dumpsys window 2>/dev/null | grep -o 'touchableRegion=SkRegion([^)]*)' | head -1)"
