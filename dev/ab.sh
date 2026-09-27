#!/system/bin/sh
APKG=com.islandbridge
URI=content://com.islandbridge.events

echo "### A) clear the island strip, capture BASELINE ###"
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"done"}' | base64 -w0)" >/dev/null 2>&1
am force-stop $APKG; sleep 4
screencap -p /data/local/tmp/base.png 2>/dev/null && echo "  baseline captured"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1

echo
echo "### B) wake the DEAD app via Binder with a big obvious card ###"
logcat -c 2>/dev/null
content call --uri $URI --method event \
  --extra evb:s:"$(echo -n '{"t":"chat.start","cid":"c1","cname":"测试会话","mid":"m1"}' | base64 -w0)"
sleep 2
content call --uri $URI --method event \
  --extra evb:s:"$(echo -n '{"t":"chat.delta","cid":"c1","mid":"m1","kind":"text","text":"这是通过Binder穿透冻结送达的回复内容 12345"}' | base64 -w0)"
sleep 5

echo "  --- app log ---"
logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -8
echo "  --- island geometry now ---"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
echo "  --- freeze: pid=[$(pidof $APKG)] freeze=[$(cat /sys/fs/cgroup/apps/uid_10370/cgroup.freeze 2>/dev/null)]"

screencap -p /data/local/tmp/card.png 2>/dev/null && echo "  card captured"
