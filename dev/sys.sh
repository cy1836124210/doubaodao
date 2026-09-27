#!/system/bin/sh
echo "########## 1. OPLUS Hans kernel module — does it support NETWORK thaw? ##########"
if [ -d /sys/module/oplus_sys_hans ]; then
  echo "  module present: $(ls /sys/module/oplus_sys_hans/)"
  for f in /sys/module/oplus_sys_hans/parameters/*; do
    [ -e "$f" ] && echo "    $(basename $f) = $(cat $f 2>/dev/null)"
  done
  echo "  --- refcnt/version ---"
  cat /sys/module/oplus_sys_hans/refcnt 2>/dev/null
fi
echo "  --- any network-thaw knob in the whole kernel tree? ---"
grep -rl . /sys/module/*/parameters/ 2>/dev/null | xargs grep -il "thaw\|unfreez" 2>/dev/null | head -5

echo
echo "########## 2. WHO is immune to the freezer? ##########"
for u in 1000 10246 10370; do
  if [ -d /sys/fs/cgroup/apps/uid_$u ]; then
    echo "  uid_$u : freezable cgroup EXISTS  freeze=$(cat /sys/fs/cgroup/apps/uid_$u/cgroup.freeze 2>/dev/null)"
  else
    echo "  uid_$u : NO freezable cgroup  <-- CANNOT BE FROZEN"
  fi
done
echo "  systemui(10246) memory group: $(grep memory /proc/$(pidof com.android.systemui)/cgroup 2>/dev/null)"
echo "  system_server(1000) memory:  $(grep memory /proc/$(pidof system_server)/cgroup 2>/dev/null)"

echo
echo "########## 3. Is our LSPosed module ALREADY running inside SystemUI? ##########"
L=/data/adb/lspd/log
ls -t $L/modules_*.log 2>/dev/null | head -1 | while read f; do
  echo "  log: $f"
  grep -a "com.android.systemui" "$f" 2>/dev/null | grep -a "com.islandbridge" | tail -5
done
echo "  --- is com.islandbridge in SystemUI's loaded modules? ---"
grep -a "SystemUI" $L/modules_*.log 2>/dev/null | grep -ac "com.islandbridge" 

echo
echo "########## 4. AstraIsland's own code runs inside SystemUI (same process as us) ##########"
ls -t $L/modules_*.log 2>/dev/null | head -1 | while read f; do
  grep -a "com.astraflow.tool" "$f" 2>/dev/null | grep -a "com.android.systemui" | tail -6
done

echo
echo "########## 5. What the island exposes inside SystemUI ##########"
echo "  --- astraflow's own process? (if empty, it ONLY lives inside SystemUI) ---"
echo "  pidof com.astraflow.tool = '$(pidof com.astraflow.tool)'"
echo "  cgroup dir for its uid 10050: $([ -d /sys/fs/cgroup/apps/uid_10050 ] && echo EXISTS || echo NONE)"
echo "  --- the island's message history db (proves state lives in SystemUI) ---"
ls -la /data/user_de/0/com.android.systemui/cache/astraflow-island*.sqlite* 2>/dev/null

echo
echo "########## 6. cached_apps_freezer + freezer cutoff ##########"
settings get global cached_apps_freezer 2>/dev/null
dumpsys activity 2>/dev/null | grep -i "freezer_cutoff_adj"
