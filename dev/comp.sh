#!/system/bin/sh
# Does a COMPONENT START (not a broadcast) penetrate the freeze?
AUID=10370
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze
wchan() { for p in $(pidof $APKG 2>/dev/null); do echo "     pid $p -> $(cat /proc/$p/wchan 2>/dev/null)"; done; }

echo "=== baseline ==="
echo "  freeze=$(cat $CF)"; wchan

echo
echo "=== freeze it ==="
echo 1 > $CF; sleep 2
echo "  freeze=$(cat $CF)"; wchan

echo
echo "=== A) BROADCAST while frozen (the channel we use today) ==="
am broadcast -a com.islandbridge.KEEPALIVE -n $APKG/.KeepAliveReceiver >/dev/null 2>&1
sleep 3
echo "  freeze=$(cat $CF)"; wchan
echo "  deferred entries: $(dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest $APKG")"

echo
echo "=== B) COMPONENT START while frozen (exported activity as the probe) ==="
am start -n $APKG/.MainActivity >/dev/null 2>&1
sleep 3
echo "  freeze=$(cat $CF)"; wchan
echo "  focus: $(dumpsys window 2>/dev/null | grep -m1 mCurrentFocus)"

echo
echo "=== C) what did the app log? ==="
logcat -d -t 80 2>/dev/null | grep -iE "islandbridge|ActivityManager.*islandbridge|Freezer" | tail -15

echo
echo "=== restore: HOME + unfreeze ==="
input keyevent KEYCODE_HOME; sleep 1
echo 0 > $CF; sleep 1
echo "  freeze=$(cat $CF)"

echo
echo "=== OPLUS not_restrict.xml: what does our entry look like? ==="
grep -o -E ".{80}com\.islandbridge.{80}" /data/oplus/os/battery/not_restrict.xml 2>/dev/null
echo "--- does it mention wechat? ---"
grep -o -E ".{60}com\.tencent\.mm.{60}" /data/oplus/os/battery/not_restrict.xml 2>/dev/null
