#!/system/bin/sh
APKG=com.islandbridge
URI=content://com.islandbridge.events
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
PILL() { dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1; }

echo "############ A. root runtime: exactly one worker each, no dupes ############"
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/relay*|*islandbridge/listen*) echo "  ${d#/proc/}: $c" ;; esac
done
echo "  baseline pill: $(PILL)"

echo
echo "############ B. COLD START: app fully killed, event arrives over TCP ############"
am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"reset"}' | base64 -w0)" >/dev/null 2>&1
sleep 4
am force-stop $APKG; sleep 3
logcat -c 2>/dev/null
echo "  app dead: pid=[$(pidof $APKG)]"
echo "  pill after reset: $(PILL)"

echo
echo "  --- inject via LAN listener (simulating PC on the configured IP) ---"
printf 'zqtok123\t{"t":"plan.start","tid":"final","title":"豆包正在思考","total":0}\n' | nc 127.0.0.1 8799
sleep 7
echo "  app pid: [$(pidof $APKG)]  freeze=[$(cat $CF 2>/dev/null)]"
echo "  pill NOW: $(PILL)"
echo "     (baseline was 563..1030 = 467px wide; a card widens it)"

echo
echo "  --- relay log ---"
tail -5 /data/local/tmp/islandbridge_relay.log
echo "  --- app log ---"
logcat -d 2>/dev/null | grep -E "IslandBridge:" | tail -8

echo
echo "############ C. streaming while frozen (chat.delta) ############"
i=1; OK=0
while [ $i -le 12 ]; do
  printf 'zqtok123\t{"t":"chat.delta","cid":"c1","mid":"m1","kind":"text","text":"流式内容%d "\}\n' $i | nc 127.0.0.1 8799
  i=$((i+1))
done
sleep 6
echo "  deltas delivered to pipeline: $(logcat -d 2>/dev/null | grep -c 'ev ok chat.delta')"
echo "  freeze while streaming: [$(cat $CF 2>/dev/null)]"
echo "  pill: $(PILL)"

screencap -p /data/local/tmp/final.png 2>/dev/null && echo "  screenshot saved"
