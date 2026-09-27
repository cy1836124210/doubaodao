#!/system/bin/sh
L=/data/local/tmp/sock.log
PID=$(pidof com.islandbridge | awk '{print $1}')
: > $L
echo "pid=$PID" >> $L

echo "=== thread states (R = actually running) ===" >> $L
for t in /proc/$PID/task/*; do
  n=$(basename $t)
  s=$(awk '{print $3}' $t/stat 2>/dev/null)
  nm=$(cat $t/comm 2>/dev/null)
  echo "  $n $s $nm" >> $L
done

echo "=== listening sockets ===" >> $L
cat /proc/$PID/net/tcp /proc/$PID/net/tcp6 2>/dev/null | awk '$4=="0A"{print "  LISTEN "$2}' | sort -u >> $L
awk '$4=="0A"{print "  LISTEN "$2}' /proc/net/unix 2>/dev/null >> $L

echo "=== established connections (odd = to PC) ===" >> $L
cat /proc/$PID/net/tcp 2>/dev/null | awk 'NR>1 && $4=="01"{print "  ESTAB "$2" -> "$3}' >> $L

echo "=== all unix sockets owned by this uid ===" >> $L
cat /proc/net/unix 2>/dev/null | grep -c . >> $L
cat /proc/net/unix 2>/dev/null | awk '$0 ~ /island|bridge|sse/{print "  "$0}' >> $L

echo "=== end ===" >> $L
