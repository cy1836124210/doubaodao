#!/system/bin/sh
# Why is astraflow (10050) never frozen while islandbridge (10370) is?
O=/data/local/tmp/why.txt
: > $O

echo "### apps cgroup tree" >> $O
ls /sys/fs/cgroup/apps/ 2>/dev/null | head -40 >> $O

echo "### astraflow running? where does its process live?" >> $O
AP=$(pidof com.astraflow.tool)
echo "astraflow pids: $AP" >> $O
for p in $AP; do echo "  pid $p cgroup: $(tr '\n' '|' < /proc/$p/cgroup)" >> $O; done
echo "  uid_10050 dir exists? $(ls -d /sys/fs/cgroup/apps/uid_10050 2>&1)" >> $O

echo "### islandbridge process cgroups + freeze" >> $O
for p in $(pidof com.islandbridge); do
  echo "  pid $p: $(tr '\n' '|' < /proc/$p/cgroup)" >> $O
done
for u in 10370 10050 10375 10246; do
  echo "  uid_$u v2freeze=$(cat /sys/fs/cgroup/apps/uid_$u/cgroup.freeze 2>/dev/null)" >> $O
done

echo "### cached_apps_freezer setting" >> $O
settings get global cached_apps_freezer >> $O 2>&1
settings get secure cached_apps_freezer >> $O 2>&1
getprop | grep -iE 'freez|frozen' >> $O 2>&1

echo "### freezer dumpsys" >> $O
dumpsys activity processes 2>/dev/null | grep -iE 'freez' | head -30 >> $O

echo "### FGS notification of islandbridge" >> $O
dumpsys notification --noredact 2>/dev/null | grep -A6 'islandbridge' | head -30 >> $O

echo "### astraflow package flags (persistent? system?)" >> $O
dumpsys package com.astraflow.tool 2>/dev/null | grep -E 'flags=|pkgFlags|userId=|codePath' | head -8 >> $O
echo "--- islandbridge flags ---" >> $O
dumpsys package com.islandbridge 2>/dev/null | grep -E 'flags=|pkgFlags|userId=|codePath' | head -8 >> $O

echo "### which app-states does OPPO report" >> $O
dumpsys activity processes 2>/dev/null | grep -B2 -A8 'ProcessRecord.*islandbridge' | head -40 >> $O
cat $O
