#!/system/bin/sh
# (A) Find the whitelist that exempts com.astraflow.tool (uid 10050) from freeze
# (B) Test whether SERVICE/binder path still works while broadcast is deferred
L=/data/local/tmp/binder.log
: > $L

echo "=== A1: cgroup.freeze existence per uid ===" >> $L
for u in 10050 10370 10375; do
  d=/sys/fs/cgroup/apps/uid_$u
  if [ -d $d ]; then
    echo "  uid_$u EXISTS freeze=$(cat $d/cgroup.freeze 2>/dev/null)" >> $L
  else
    echo "  uid_$u NO_DIR (never frozen)" >> $L
  fi
done

echo "=== A2: what lists astraflow? ===" >> $L
for d in /data/oplus/os /data/system /data/oplus; do
  grep -rl "astraflow" $d 2>/dev/null | head -20 >> $L
done

echo "=== A3: oplus app freeze config ===" >> $L
grep -rl "islandbridge\|astraflow" /data/system/*.xml /data/system/*/*.xml 2>/dev/null | head -20 >> $L

echo "=== B1: service path - BridgeService before ===" >> $L
dumpsys activity services com.islandbridge 2>/dev/null | grep -E 'lastStartId|startRequested|isForeground' | head -4 >> $L

echo "=== B2: am startservice (binder/service path, NOT broadcast) ===" >> $L
am startservice -n com.islandbridge/.BridgeService 2>&1 >> $L
sleep 3
echo "  after:" >> $L
dumpsys activity services com.islandbridge 2>/dev/null | grep -E 'lastStartId|startRequested|isForeground' | head -4 >> $L

echo "=== B3: broadcast control (should be deferred) ===" >> $L
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver --es t probe 2>&1 >> $L

echo "=== end ===" >> $L
