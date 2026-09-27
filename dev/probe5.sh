#!/system/bin/sh
L=/data/local/tmp/probe5.log
R=com.islandbridge/.BridgeEventReceiver
: > $L
j(){ printf '{"t":"chat.delta","mid":"%s","kind":"text","text":"%s"}' "$1" "$1"; }
b64(){ printf '%s' "$1" | base64 -w0; }
pend(){ dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest com.islandbridge"; }

PID=$(pidof com.islandbridge | awk '{print $1}')
echo "pid=$PID" >> $L

echo "=== L1 scheduling timeline: does utime advance while backgrounded? ===" >> $L
i=0
while [ $i -lt 7 ]; do
  awk -v i=$i '{print "  t="i*5"s state="$3" utime="$14" stime="$15}' /proc/$PID/stat >> $L 2>&1
  i=$((i+1)); sleep 5
done

echo "=== L2 oplus/freeze shell services ===" >> $L
cmd -l 2>/dev/null | grep -iE 'freeze|hans|oplus|power|startup' >> $L

echo "=== L3 --receiver-foreground (pending before=$(pend)) ===" >> $L
am broadcast -a com.islandbridge.EVENT -n $R --ei v 2 --es evb "$(b64 "$(j RF1)")" --receiver-foreground >> $L 2>&1
sleep 4
echo "  pending after=$(pend)" >> $L

echo "=== L4 FLAG_RECEIVER_FOREGROUND 0x10000000 ===" >> $L
am broadcast -a com.islandbridge.EVENT -n $R --ei v 2 --es evb "$(b64 "$(j RF2)")" -f 0x10000000 >> $L 2>&1
sleep 4
echo "  pending after=$(pend)" >> $L

echo "=== L5 app-thread liveness: files opened by main pid ===" >> $L
ls -l /proc/$PID/fd 2>/dev/null | wc -l >> $L

echo "=== end $(date +%H:%M:%S) ===" >> $L
