#!/system/bin/sh
echo "### SystemUI uid + is it ever frozen? ###"
for p in $(pidof com.android.systemui); do
  echo "pid=$p uid=$(stat -c %u /proc/$p 2>/dev/null)"
done
echo "uid_10246 cgroup.freeze = $(cat /sys/fs/cgroup/apps/uid_10246/cgroup.freeze 2>/dev/null)"
echo "uid_10246 cgroup.events:"; cat /sys/fs/cgroup/apps/uid_10246/cgroup.events 2>/dev/null
echo "  (frozen 0 forever = SystemUI is exempt)"
echo
echo "### our uid freeze for contrast ###"
echo "uid_10370 cgroup.freeze = $(cat /sys/fs/cgroup/apps/uid_10370/cgroup.freeze 2>/dev/null)"
echo "uid_10370 cgroup.events:"; cat /sys/fs/cgroup/apps/uid_10370/cgroup.events 2>/dev/null
echo
echo "### which uid does the island host (astraflow) live in? ###"
echo "astraflow pid: $(pidof com.astraflow.tool)"
dumpsys activity processes 2>/dev/null | grep -E "com.astraflow.tool" | head -5
echo
echo "### memory group of systemui (apps/active = never frozen) ###"
cat /proc/$(pidof com.android.systemui)/cgroup 2>/dev/null | tr '\n' ' '
echo
echo "### OPLUS hans/whitelist state for our app ###"
dumpsys activity 2>/dev/null | grep -iE "hans|preload|freeze" | head -10
