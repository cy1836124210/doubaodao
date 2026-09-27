#!/system/bin/sh
# Timeline: is com.islandbridge actually frozen/scheduled while in background?
L=/data/local/tmp/timeline.log
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
: > $L
i=0
while [ $i -lt 18 ]; do
  PID=$(pidof com.islandbridge | awk '{print $1}')
  ST=$(awk '{print $3}' /proc/$PID/stat 2>/dev/null)
  UT=$(awk '{print $14}' /proc/$PID/stat 2>/dev/null)
  NT=$(ls /proc/$PID/task 2>/dev/null | wc -l)
  FZ=$(cat $CF 2>/dev/null)
  STC=$(dumpsys activity processes com.islandbridge 2>/dev/null | grep -m1 'state: cur=' | tr -d ' ')
  echo "t=$((i*5))s pid=$PID cgfreeze=$FZ pstate=$ST utime=$UT threads=$NT $STC" >> $L
  i=$((i+1))
  sleep 5
done
echo "end" >> $L
