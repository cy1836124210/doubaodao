#!/system/bin/sh
# Definitive causal test, bridge app in BACKGROUND, Doubao FOREGROUND.
L=/data/local/tmp/causal.log
: > $L
J=$(ls -t /data/adb/lspd/log/modules_*.log 2>/dev/null | head -1)
echo "lspdlog=$J" >> $L

echo "--- relay process state" >> $L
pgrep -f ib_relay >> $L 2>&1 || echo "  NO_RELAY_RUNNING" >> $L
echo "  pidfile=$(cat /data/data/com.islandbridge/files/ib_relay.pid 2>/dev/null)" >> $L
echo "  ibq.log=$(ls -l /data/data/com.larus.nova/files/ibq.log 2>/dev/null)" >> $L

echo "--- hook-side: last ev[] lines BEFORE" >> $L
grep -a "ev\[" "$J" 2>/dev/null | tail -3 >> $L

echo "--- bridge app visibility" >> $L
dumpsys window 2>/dev/null | grep -m1 mCurrentFocus >> $L

echo "--- marker" >> $L
