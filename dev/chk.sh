#!/system/bin/sh
echo "=== module loaded where? ==="
grep -ao '([a-z0-9._]*)\[com.islandbridge' /data/adb/lspd/log/modules_*.log 2>/dev/null | sort -u
echo "=== provider record ==="
dumpsys activity providers 2>/dev/null | grep -c "com.islandbridge.events"
echo "=== app pid / frozen ==="
pidof com.islandbridge
cat /sys/fs/cgroup/apps/uid_10370/cgroup.freeze 2>/dev/null
echo "=== relay alive? ==="
cat /data/data/com.islandbridge/files/ib_relay.pid 2>/dev/null
echo "---"
ps -A -o PID,ARGS 2>/dev/null | grep -E "ib_relay|relay" | grep -v grep
