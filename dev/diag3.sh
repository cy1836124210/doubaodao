#!/system/bin/sh
PIDFILE=/data/data/com.islandbridge/files/ib_relay.pid
F=/data/data/com.larus.nova/files/ibq.log

echo "### ps capability (does -o ARGS work?) ###"
ps -A 2>&1 | head -3
echo "  lines from 'ps -A': $(ps -A 2>/dev/null | wc -l)"
echo "  lines from 'ps -A -o PID,ARGS': $(ps -A -o PID,ARGS 2>/dev/null | wc -l)"

echo
echo "### /proc scan (authoritative) ###"
echo "  -- our relay --"
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *ib_relay*|*islandbridge*) echo "     $p: $c" ;; esac
done
echo "  -- every sh-like process --"
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in sh\ *|*/sh\ *|*/sh) echo "     $p: $c" ;; esac
done

echo
echo "### pidfile ###"
P=$(cat $PIDFILE 2>/dev/null)
echo "  pidfile=[$P]  /proc/$P exists: $([ -d /proc/$P ] && echo YES || echo NO)"
[ -d /proc/$P ] && echo "  cmdline: $(tr '\0' ' ' < /proc/$P/cmdline 2>/dev/null)"

echo
echo "### queue files ###"
ls -l $F* 2>/dev/null || echo "  none"

echo
echo "### root daemon plumbing ###"
echo "  service.d: $(ls /data/adb/service.d/ 2>/dev/null | tr '\n' ' ')"
echo "  ksu version: $(cat /data/adb/ksu/version 2>/dev/null)"
echo "  module.prop: $(head -3 /data/adb/modules/*/module.prop 2>/dev/null | head -6)"
