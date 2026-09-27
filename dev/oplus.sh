#!/system/bin/sh
L=/data/local/tmp/oplus.log
: > $L
echo "=== bpm dir ===" >> $L
ls -la /data/oplus/os/bpm/ 2>/dev/null >> $L
echo "=== hans dir ===" >> $L
ls -la /data/oplus/os/hans/ 2>/dev/null >> $L
find /data/oplus -iname '*hans*' -o -iname '*freeze*' -o -iname '*bpm*' 2>/dev/null | head -30 >> $L
echo "=== dumpsys candidates ===" >> $L
for s in oplus_freeze hans oplus_app_cache_service power oplusbattery; do
  echo "--- $s" >> $L
  dumpsys $s 2>&1 | head -12 >> $L
done
echo "=== module_configs / lspd_configs for freeze ===" >> $L
echo "=== OPPO app power policy for our uids ===" >> $L
dumpsys activity processes 2>/dev/null | grep -B2 -A2 'uid_10370' | head -20 >> $L
echo "=== end ===" >> $L
