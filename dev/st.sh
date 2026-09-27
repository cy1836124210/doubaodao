#!/system/bin/sh
# Verify all three requirements:
#  1. pill shows ONLY status (手机·正在回复 -> 手机·回答完毕), no body text
#  2. expanded card body streams the NEWEST segment during the reply
#  3. 手机/电脑 label present
APKG=com.islandbridge
URI=content://com.islandbridge.events

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2
input keyevent KEYCODE_HOME; sleep 2
logcat -c 2>/dev/null

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

echo "### 1) MOBILE source ###"
send '{"t":"chat.start","cid":"cS","cname":"状态测试","mid":"mS"}'
sleep 6
echo "  -- pill while replying --"
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -3

# stream a long reply; each segment unique so we can see which is displayed
i=1
while [ $i -le 12 ]; do
  send "{\"t\":\"chat.delta\",\"cid\":\"cS\",\"mid\":\"mS\",\"kind\":\"text\",\"text\":\"最新段$i。\"}"
  i=$((i+1))
done
sleep 4
echo
echo "  -- card body during stream (should be a SHORT NEWEST segment, not the head) --"
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -4

echo
echo "  opening the card (swipe down on the pill) to read it..."
input swipe 1440 400 700 1200 300 2>/dev/null
sleep 3
screencap -p /data/local/tmp/o1.png
input keyevent KEYCODE_BACK; sleep 1

echo
echo "### 2) end -> 回答完毕 + full body ###"
send '{"t":"chat.end","cid":"cS","mid":"mS"}'
sleep 4
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -3
screencap -p /data/local/tmp/o2.png

echo
echo "### 3) PC source ###"
am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3; am force-stop $APKG; sleep 2
# no cname/cid -> treated as PC (fromMobile=false) via the broadcast path label
send '{"t":"chat.start","cid":"cP","cname":"电脑会话","mid":"mP"}'
sleep 6
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -2

echo
echo "### pill ###"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
