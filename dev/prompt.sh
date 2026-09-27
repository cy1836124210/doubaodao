#!/system/bin/sh
APKG=com.islandbridge
D=com.larus.nova
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
PILL() { dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1; }
TYPE="com.oplus.keyboard/.service.ImeService"

echo "### input method ###"
ime set $TYPE >/dev/null 2>&1
ime list -s 2>/dev/null | head -3

echo
echo "### state before ###"
echo "  app pid=[$(pidof $APKG)]   doubao pid=[$(pidof $D)]"
echo "  pill: $(PILL)"

echo
echo "### type a prompt into Doubao ###"
# input field bounds from earlier reverse: [48,2833][1216,3120]
input tap 632 2976
sleep 2
input text "hello"
sleep 2
# send button: node action_send bounds [1216,2896][1392,3120]
input tap 1304 3008
echo "  sent"

echo
echo "### watch for the app to be woken by a REAL Doubao event ###"
for i in 1 2 3 4 5 6 7 8 9 10; do
    sleep 3
    P=$(pidof $APKG)
    F=$(cat $CF 2>/dev/null)
    echo "  t=$((i*3))s  app_pid=[$P] freeze=[$F]  pill=$(PILL | grep -o 'SkRegion([^)]*)')"
done
echo
echo "### app pipeline ###"
logcat -d 2>/dev/null | grep -E "IslandBridge" | tail -15
