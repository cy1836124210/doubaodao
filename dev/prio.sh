#!/system/bin/sh
# Does RAISING PRIORITY prevent the freeze?  (the user's hypothesis)
AUID=10370; APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze

snap() {
  echo "   freeze=$(cat $CF 2>/dev/null)"
  for p in $(pidof $APKG 2>/dev/null); do
    echo "   pid=$p oom_score_adj=$(cat /proc/$p/oom_score_adj 2>/dev/null) wchan=$(cat /proc/$p/wchan 2>/dev/null)"
  done
  dumpsys activity processes 2>/dev/null | awk '/\*APP\* UID 10370/{f=1} f&&/oom adj|curProcState|isFreezeExempt|isFrozen|shouldNotFreeze/{print "   "$0} f&&/^$/{exit+0}'
  echo "   deferred-for-us: $(dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest $APKG")"
}

echo "############ BASELINE (app just backgrounded) ############"
input keyevent KEYCODE_HOME; sleep 6
snap

echo
echo "############ LEVER 1: doze whitelist ############"
cmd deviceidle whitelist +$APKG 2>&1 | head -2
sleep 3; snap

echo
echo "############ LEVER 2: standby bucket -> active ############"
am set-standby-bucket $APKG active 2>&1 | head -2
sleep 3; snap

echo
echo "############ LEVER 3: appops RUN_ANY_IN_BACKGROUND allow ############"
cmd appops set $APKG RUN_ANY_IN_BACKGROUND allow 2>&1 | head -2
cmd appops set $APKG RUN_IN_BACKGROUND allow 2>&1 | head -2
sleep 3; snap

echo
echo "############ LEVER 4: oom_score_adj -> -1000 (kernel max priority) ############"
for p in $(pidof $APKG 2>/dev/null); do
  echo -1000 > /proc/$p/oom_score_adj 2>/dev/null && echo "   set -1000 on $p" || echo "   FAILED on $p"
done
sleep 3; snap

echo
echo "############ LEVER 5: force-freeze anyway -> does the freeze still stick? ############"
echo 1 > $CF; sleep 3
echo "   after forcing freeze=1:"
snap
echo 0 > $CF; sleep 1

echo
echo "############ OPLUS hans knobs ############"
for f in /sys/module/oplus_sys_hans/parameters/*; do
  [ -e "$f" ] && echo "   $(basename $f) = $(cat $f 2>/dev/null)"
done 2>/dev/null | head -25

input keyevent KEYCODE_HOME
