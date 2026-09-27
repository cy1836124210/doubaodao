#!/system/bin/sh
# Verify the pill now follows the TAIL of the stream.
APKG=com.islandbridge
URI=content://com.islandbridge.events

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2
# go HOME so the island is visible (hideWhenSourceForeground is false, but the
# card sits on the island which shows over the launcher more reliably)
input keyevent KEYCODE_HOME
sleep 2
logcat -c 2>/dev/null

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

send '{"t":"chat.start","cid":"cV","cname":"验证","mid":"mV"}'
sleep 5
echo "  card up pid=[$(pidof $APKG)]"

# 1) unique head token
send '{"t":"chat.delta","cid":"cV","mid":"mV","kind":"text","text":"AAA头部标记 "}'
sleep 1

# 2) a long middle so the buffer far exceeds one screen
i=1
MID=""
while [ $i -le 40 ]; do MID="$MID中间内容$i。"; i=$((i+1)); done
send "{\"t\":\"chat.delta\",\"cid\":\"cV\",\"mid\":\"mV\",\"kind\":\"text\",\"text\":\"$MID\"}"
sleep 1
screencap -p /data/local/tmp/v1.png

# 3) unique TAIL token, appended at the very end
send '{"t":"chat.delta","cid":"cV","mid":"mV","kind":"text","text":"ZZZ尾部标记"}'
sleep 3
screencap -p /data/local/tmp/v2.png
echo "  captured v1 (before tail) and v2 (after tail)"

echo
echo "### does the astraflow/island module log the payload it received? ###"
logcat -d 2>/dev/null | grep -iE "astraflow|astraisland|island" | tail -15

echo
echo "### pill width ###"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
