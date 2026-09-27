#!/system/bin/sh
APKG=com.islandbridge
URI=content://com.islandbridge.events

am force-stop $APKG
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.end","tid":"plan","success":true,"text":"r"}' | base64 -w0)" >/dev/null 2>&1
sleep 3
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null

send() { printf 'zqtok123\t%s\n' "$1" | nc 127.0.0.1 8799; }

send '{"t":"chat.start","cid":"cE","cname":"结束测试","mid":"mE"}'
sleep 6
send '{"t":"chat.delta","cid":"cE","mid":"mE","kind":"text","text":"这是一段回复内容。"}'
sleep 2
echo "=== BEFORE end ==="
send '{"t":"chat.end","cid":"cE","mid":"mE"}'
sleep 5

echo
echo "=== ALL IslandBridge lines ==="
logcat -d 2>/dev/null | grep "IslandBridge" | tail -30
echo
echo "=== did the end event arrive? ==="
logcat -d 2>/dev/null | grep -c "ev ok chat.end"
echo
echo "=== any exception / rc != 0 ? ==="
logcat -d 2>/dev/null | grep -E "IslandBridge.*(rc=|Exception|岛card|失败|error)" | tail -15
