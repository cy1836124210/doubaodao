#!/system/bin/sh
# Demo: synthetic stream over TCP (shows the 电脑 label), collapsed + expanded.
APKG=com.islandbridge
URI=content://com.islandbridge.events
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2
input keyevent KEYCODE_HOME; sleep 2

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

send '{"t":"chat.start","cid":"cDem","cname":"演示会话","mid":"mDem"}'
sleep 6
echo "  card up: pid=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)]"

# stream some content so the card has a body
send '{"t":"chat.delta","cid":"cDem","mid":"mDem","kind":"text","text":"这是一段正在流式输出的回复内容，"}'
sleep 1
send '{"t":"chat.delta","cid":"cDem","mid":"mDem","kind":"text","text":"卡片会实时显示最新的片段。"}'
sleep 3
screencap -p /data/local/tmp/d1_collapsed.png
echo "  captured collapsed pill"

# expand: swipe down from the pill
input swipe 720 60 720 1000 400
sleep 3
screencap -p /data/local/tmp/d2_expanded.png
echo "  captured expanded card"

# keep streaming so the expanded card visibly updates
send '{"t":"chat.delta","cid":"cDem","mid":"mDem","kind":"text","text":"新增的第三段内容，展开卡片里应该能看到。"}'
sleep 3
screencap -p /data/local/tmp/d3_streaming.png
echo "  captured expanded card after more text"

# end -> 回答完毕
send '{"t":"chat.end","cid":"cDem","mid":"mDem"}'
sleep 4
screencap -p /data/local/tmp/d4_done.png
echo "  captured done state"

echo
echo "  states:"
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -5
