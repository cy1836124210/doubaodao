#!/system/bin/sh
echo "### cgroup of key processes ###"
for p in $(pidof com.android.systemui) $(pidof system_server) $(pidof com.astraflow.tool) $(pidof com.islandbridge); do
  nm=$(cat /proc/$p/cmdline 2>/dev/null | tr '\0' ' ')
  echo "pid=$p  ($nm)"
  echo "   $(cat /proc/$p/cgroup 2>/dev/null | tr '\n' ' ')"
done

echo
echo "### count of per-uid freezable dirs ###"
ls -d /sys/fs/cgroup/apps/uid_* 2>/dev/null | wc -l

echo "### does uid_1000 (system) have a freeze dir? ###"
if [ -d /sys/fs/cgroup/apps/uid_1000 ]; then
  echo "YES uid_1000 exists; freeze=$(cat /sys/fs/cgroup/apps/uid_1000/cgroup.freeze 2>/dev/null)"
else
  echo "NO uid_1000 dir -> system uid is NOT freeze-managed"
fi

echo "### is systemui inside any apps/uid_* dir? ###"
sp=$(pidof com.android.systemui)
grep -l . /dev/null 2>/dev/null
for d in /sys/fs/cgroup/apps/uid_*; do
  if [ -e "$d/pid_$sp" ]; then echo "  systemui IS in $d"; fi
done
echo "(no line above = systemui is outside all freeze groups)"

echo
echo "### noactive / fkcoloros present? ###"
pm list packages 2>/dev/null | grep -E "noactive|fkcoloros|superlyric"
