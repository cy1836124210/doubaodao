#!/system/bin/sh
# DECISIVE: is cgroup freeze (not merely broadcast defer) the real cause?
O=/data/local/tmp/thaw.txt
: > $O
C=/sys/fs/cgroup/apps/uid_10370

echo "=== full cgroup membership of pid $(pidof com.islandbridge) ===" >> $O
cat /proc/$(pidof com.islandbridge)/cgroup >> $O 2>&1
echo "state=$(cut -d' ' -f3 /proc/$(pidof com.islandbridge)/stat 2>/dev/null)" >> $O
echo "=== v2 root check: is pid_9030 under uid_10370? ===" >> $O
ls -d /sys/fs/cgroup/apps/uid_10370/pid_* >> $O 2>&1

echo "=== BEFORE: freeze=$(cat $C/cgroup.freeze 2>/dev/null) events=$(tr '\n' ',' < $C/cgroup.events) ===" >> $O
logcat -c 2>/dev/null

echo "--- A: broadcast while frozen ---" >> $O
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
  --ei v 1 --es ev '{"t":"chat.delta","mid":"THAW_A","kind":"text","text":"A"}' >/dev/null 2>&1
sleep 4
echo "  recvA=$(logcat -d -s IslandBridge:I 2>/dev/null | grep -c 'THAW_A')" >> $O
echo "  deferred=$(dumpsys activity broadcasts 2>/dev/null | grep -c 'DEFERRED for manifest com.islandbridge')" >> $O

echo "--- B: THAW the cgroup, then broadcast ---" >> $O
echo 0 > $C/cgroup.freeze 2>>$O
sleep 1
echo "  after-thaw freeze=$(cat $C/cgroup.freeze 2>/dev/null) events=$(tr '\n' ',' < $C/cgroup.events)" >> $O
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
  --ei v 1 --es ev '{"t":"chat.delta","mid":"THAW_B","kind":"text","text":"B"}' >/dev/null 2>&1
sleep 4
echo "  recvB=$(logcat -d -s IslandBridge:I 2>/dev/null | grep -c 'THAW_B')" >> $O
echo "  logcatB:" >> $O
logcat -d -s IslandBridge:I 2>/dev/null | grep -E 'THAW|recv' | tail -6 >> $O

echo "=== C: does OPPO re-freeze us? sample 20s ===" >> $O
for i in 1 2 3 4 5 6 7 8 9 10; do
  echo "  t=$i freeze=$(cat $C/cgroup.freeze 2>/dev/null)" >> $O
  sleep 2
done
echo "=== D: broadcast after the window ===" >> $O
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
  --ei v 1 --es ev '{"t":"chat.delta","mid":"THAW_D","kind":"text","text":"D"}' >/dev/null 2>&1
sleep 4
echo "  recvD=$(logcat -d -s IslandBridge:I 2>/dev/null | grep -c 'THAW_D')" >> $O

echo "=== E: what does OPPO set our procstate to? ===" >> $O
dumpsys activity processes com.islandbridge 2>/dev/null | grep -E 'isFrozen|curProcState|setProcState' | head -4 >> $O
cat $O
