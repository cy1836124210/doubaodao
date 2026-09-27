#!/system/bin/sh
echo "########## service.d 现状（必须只有一个 launcher） ##########"
ls -l /data/adb/service.d/
echo "--- head of islandbridge.sh ---"
head -4 /data/adb/service.d/islandbridge.sh 2>/dev/null

echo
echo "########## workers ##########"
ls -l /data/adb/islandbridge/ 2>/dev/null || echo "  MISSING"

echo
echo "########## 存活进程 ##########"
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/relay*|*islandbridge/listen*|*service.d/islandbridge*) echo "  ${d#/proc/}: $c" ;; esac
done

echo
echo "########## 监听端口 ##########"
netstat -tlnp 2>/dev/null | grep -E ":87(99|87)" || echo "  (无监听)"

echo
echo "########## relay 日志 ##########"
tail -8 /data/local/tmp/islandbridge_relay.log 2>/dev/null || echo "  (无日志)"

echo
echo "########## 模块加载状态 ##########"
grep -ao '([a-z0-9._]*)\[com.islandbridge' /data/adb/lspd/log/modules_*.log 2>/dev/null | sort -u
