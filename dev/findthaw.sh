#!/system/bin/sh
# Find the REAL freeze control + test manual thaw.
L=/data/local/tmp/thaw.log
PID=$(pidof com.islandbridge | awk '{print $1}')
: > $L
echo "pid=$PID" >> $L

echo "=== real cgroup of the process ===" >> $L
cat /proc/$PID/cgroup >> $L 2>&1

echo "=== every cgroup.freeze file + its value under that hierarchy ===" >> $L
CG=$(awk -F: '/^0::/{print $3}' /proc/$PID/cgroup)
echo "  cgpath=$CG" >> $L
for f in /sys/fs/cgroup$CG/cgroup.freeze /sys/fs/cgroup$CG/../cgroup.freeze; do
  [ -f "$f" ] && echo "  $f = $(cat $f 2>/dev/null)" >> $L
done
echo "  --- cgroup.events" >> $L
cat /sys/fs/cgroup$CG/cgroup.events >> $L 2>&1

echo "=== parent cgroups with freeze=1 ===" >> $L
p=$(dirname /sys/fs/cgroup$CG)
while [ "$p" != "/sys/fs/cgroup" ] && [ -n "$p" ]; do
  [ -f "$p/cgroup.freeze" ] && echo "  $p = $(cat $p/cgroup.freeze 2>/dev/null)" >> $L
  p=$(dirname $p)
done

echo "=== cmd oplus_freeze subcommands ===" >> $L
cmd oplus_freeze 2>&1 | head -20 >> $L

echo "=== cmd oplus_app_cache_service ===" >> $L
cmd oplus_app_cache_service 2>&1 | head -20 >> $L

echo "=== try thaw: write 0 to the real cgroup ===" >> $L
echo 0 > /sys/fs/cgroup$CG/cgroup.freeze 2>>$L
echo "  after write: $(cat /sys/fs/cgroup$CG/cgroup.freeze 2>/dev/null)" >> $L

sleep 6
echo "=== CPU after thaw attempt ===" >> $L
awk '{print "  state="$3" utime="$14" stime="$15}' /proc/$PID/stat >> $L 2>&1
sleep 6
awk '{print "  state="$3" utime="$14" stime="$15}' /proc/$PID/stat >> $L 2>&1
echo "=== end ===" >> $L
