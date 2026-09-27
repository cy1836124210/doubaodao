#!/system/bin/sh
# Which delivery CHANNEL thaws a frozen app?  (completes the matrix, correctly)
AUID=10370; APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze

wchan()  { for p in $(pidof $APKG 2>/dev/null); do cat /proc/$p/wchan 2>/dev/null; done | head -1; }
state()  { echo "        freeze=$(cat $CF 2>/dev/null) wchan=$(wchan)"; }

try() {
  name="$1"; shift
  echo 1 > $CF; sleep 2
  echo "  --- $name ---"
  echo "     BEFORE:"; state
  "$@" >/dev/null 2>&1
  sleep 3
  echo "     AFTER :"; state
  echo 0 > $CF; sleep 1
}

echo "############ CHANNEL MATRIX (all while force-frozen) ############"
try "BROADCAST (current design)" am broadcast -a com.islandbridge.KEEPALIVE -n $APKG/.KeepAliveReceiver
try "startService"              am startservice -a com.islandbridge.PING -n $APKG/.BridgeService
try "start-foreground-service"  am start-foreground-service -a com.islandbridge.PING -n $APKG/.BridgeService
try "CONTENT PROVIDER (binder)" content query --uri content://settings/system/name
try "ACTIVITY start"            am start -n $APKG/.MainActivity

echo
echo "############ freeze decision parameters ############"
dumpsys activity 2>/dev/null | sed -n '/Freezer settings/,/Apps frozen/p' | head -14
echo "  oom adj / prcstate of our app:"
dumpsys activity processes 2>/dev/null | awk '/\*APP\* UID 10370/{f=1} f&&/oom adj|curProcState|isFreezeExempt|isFrozen|mHasForegroundServices|lastInvisibleTime/{print "     "$0} f&&/^$/{exit+0}'

input keyevent KEYCODE_HOME; sleep 1; echo 0 > $CF
