#!/system/bin/sh
APKG=com.islandbridge
D=com.larus.nova
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze

echo "########## 1. Launch Doubao and confirm the module injects ##########"
monkey -p $D -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 12
echo "  doubao pid: [$(pidof $D)]"
echo "  module injected into (LSPosed log):"
grep -ao '([a-z0-9._:]*)\[com.islandbridge' /data/adb/lspd/log/modules_*.log 2>/dev/null | sort -u
echo "  our hook lines from Doubao process:"
logcat -d 2>/dev/null | grep -E "IslandBridge" | grep -E "hooked|ev\[|loaded in" | tail -12

echo
echo "########## 2. App state ##########"
echo "  islandbridge pid=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)]"

echo
echo "########## 3. Send a real Doubao prompt ##########"
dumpsys window 2>/dev/null | grep mCurrentFocus
