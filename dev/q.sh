#!/system/bin/sh
# Determine WHY broadcasts are deferred and whether the process can run.
O=/data/local/tmp/q.txt
: > $O

echo "### 1. process state" >> $O
pidof com.islandbridge >> $O 2>&1
dumpsys activity processes com.islandbridge 2>/dev/null | grep -E 'isFrozen|curProcState|isFreezeExempt' | head -4 >> $O

echo "### 2. cgroup freeze state" >> $O
for u in 10370 10375 10050 10246; do
  d=/sys/fs/cgroup/apps/uid_$u
  if [ -d "$d" ]; then
    echo "uid_$u freeze=$(cat $d/cgroup.freeze 2>/dev/null) events=$(tr '\n' ' ' < $d/cgroup.events 2>/dev/null)" >> $O
  else
    echo "uid_$u NO cgroup dir (never freezable)" >> $O
  fi
done

echo "### 3. relay process" >> $O
PIDF=/data/data/com.islandbridge/files/ib_relay.pid
if [ -f "$PIDF" ]; then
  rp=$(cat $PIDF)
  echo "pidfile=$rp" >> $O
  if [ -d /proc/$rp ]; then
    echo "ALIVE cmdline=$(tr '\0' ' ' < /proc/$rp/cmdline)" >> $O
  else
    echo "DEAD" >> $O
  fi
else
  echo "no pidfile" >> $O
fi
ps -A -o PID,USER,NAME 2>/dev/null | grep -E 'ib_relay|/bin/sh' | head -10 >> $O

echo "### 4. deferred broadcast records + CALLER uid" >> $O
dumpsys activity broadcasts 2>/dev/null > /data/local/tmp/bc.txt
grep -n 'islandbridge' /data/local/tmp/bc.txt | head -20 >> $O
echo "--- full record context ---" >> $O
awk '/islandbridge/{print NR": "$0}' /data/local/tmp/bc.txt | head >> $O
grep -A12 '9030:com.islandbridge' /data/local/tmp/bc.txt | head -40 >> $O

echo "### 5. any OPLUS defer policy list" >> $O
dumpsys activity broadcasts 2>/dev/null | grep -iE 'deferPolicy|DEFER_BY_OPLUS' | head -20 >> $O

echo "### 6. service lastStartId" >> $O
dumpsys activity services com.islandbridge 2>/dev/null | grep -m1 lastStartId >> $O

echo "### 7. island host binding state in systemui" >> $O
logcat -d 2>/dev/null | grep -iE 'island|astraisland' | tail -25 >> $O

echo "### DONE" >> $O
cat $O
