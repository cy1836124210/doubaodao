#!/system/bin/sh
D=com.larus.nova
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
QF=/data/data/com.larus.nova/files/ibq.log

# kill our app so the wake is a genuine cold start
am force-stop $APKG
sleep 2
logcat -c 2>/dev/null
echo "  app killed: pid=[$(pidof $APKG)]"
: > $QF 2>/dev/null

echo "### input box holds: ###"
uiautomator dump /data/local/tmp/d2.xml >/dev/null 2>&1
tr '>' '>\n' < /data/local/tmp/d2.xml 2>/dev/null |
  grep 'input_text' | grep -oE 'text="[^"]*"|bounds="[^"]*"'

echo
echo "### press the send button ###"
# send button lives at the right edge of the input row
uiautomator dump /data/local/tmp/d3.xml >/dev/null 2>&1
tr '>' '>\n' < /data/local/tmp/d3.xml 2>/dev/null |
  grep -E 'send|发送' | head -5

# tap the send arrow (right of the input box, same vertical band)
input tap 1330 1745
echo "  tapped send"

for i in 1 2 3 4 5 6 7 8; do
  sleep 4
  echo "  t=$((i*4))s app=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)] q=$(wc -l < $QF 2>/dev/null)"
done

echo
echo "### REAL DOUBAO source label ###"
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -8
echo
echo "### pipeline ###"
logcat -d 2>/dev/null | grep "IslandBridge" | tail -10
