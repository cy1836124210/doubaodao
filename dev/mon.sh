#!/system/bin/sh
# Is com.islandbridge really cgroup-frozen while it holds a foreground service?
O=/data/local/tmp/mon.txt
: > $O
echo "t=0 $(date +%T)" >> $O
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  f=$(cat /sys/fs/cgroup/apps/uid_10370/cgroup.freeze 2>/dev/null)
  e=$(cat /sys/fs/cgroup/apps/uid_10370/cgroup.events 2>/dev/null | tr '\n' ',')
  # is the main pid's task list present and what cgroup is pid 9030 in?
  cg=$(cat /proc/9030/cgroup 2>/dev/null | head -1)
  st=$(cut -d' ' -f3 /proc/9030/stat 2>/dev/null)
  echo "t=$i freeze=$f events=$e state=$st cgroup=$cg" >> $O
  sleep 2
done
echo "--- which pids live in uid_10370 ---" >> $O
for p in $(ls /sys/fs/cgroup/apps/uid_10370/ 2>/dev/null | grep '^pid_'); do
  echo "  $p -> $(tr '\0' ' ' < /proc/$(echo $p|sed s/pid_//)/cmdline 2>/dev/null)" >> $O
done
echo "--- systemui / astraflow cgroups ---" >> $O
for u in 10050 10246; do
  echo "uid_$u: freeze=$(cat /sys/fs/cgroup/apps/uid_$u/cgroup.freeze 2>/dev/null)" >> $O
done
find /sys/fs/cgroup -maxdepth 2 -name 'uid_10246' -o -maxdepth 2 -name 'uid_10050' >> $O 2>/dev/null
echo "--- top-level systemui/astraflow cgroup location ---" >> $O
for p in $(pidof com.android.systemui) $(pidof com.astraflow.tool); do
  echo "  pid $p: $(cat /proc/$p/cgroup 2>/dev/null | tr '\n' '|')" >> $O
done
cat $O
