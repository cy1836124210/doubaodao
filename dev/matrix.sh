#!/system/bin/sh
# Complete the delivery-channel matrix: which channels thaw a frozen app?
AUID=10370; APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze
state() { echo "     freeze=$(cat $CF) wchan=$(for p in $(pidof $APKG); do cat /proc/$p/wchan; done)"; }

echo "########## not_restrict.xml: is our entry real? ##########"
grep -o 'att="com.islandbridge"' /data/oplus/os/battery/not_restrict.xml && echo "  -> REAL entry" || echo "  -> not a standalone entry"
echo "  wechat standalone: $(grep -o 'att="com.tencent.mm"' /data/oplus/os/battery/not_restrict.xml | head -1)"
echo "  doubao standalone: $(grep -c 'att="com.larus.nova"' /data/oplus/os/battery/not_restrict.xml)"

echo
echo "########## matrix: freeze, then try each channel ##########"
try() {
  echo 1 > $CF; sleep 2
  echo "  [$1] before: freeze=$(cat $CF) wchan=$(for p in $(pidof $APKG); do cat /proc/$p/wchan; done)"
  shift 2
  "$@" >/dev/null 2>&1
  sleep 3
  echo "  [$1] after : freeze=$(cat $CF) wchan=$(for p in $(pidof $APKG); do cat /proc/$p/wchan; done)"
  echo 0 > $CF; sleep 1
}

try "broadcast" x am broadcast -a com.islandbridge.KEEPALIVE -n $APKG/.KeepAliveReceiver
try "startService" x am startservice -a com.islandbridge.PING -n $APKG/.BridgeService
try "bindService" x cmd activity start-service -n $APKG/.BridgeService
try "provider" x content query --uri content://com.islandbridge.probe/x
try "activity" x am start -n $APKG/.MainActivity

echo
echo "########## evidence: unfreeze reasons recorded by the framework ##########"
logcat -d 2>/dev/null | grep -iE "UnfreezeReason|freezer" | tail -15

echo
echo "########## home + clean ##########"
input keyevent KEYCODE_HOME; sleep 1
echo 0 > $CF
echo "  final freeze=$(cat $CF)"
