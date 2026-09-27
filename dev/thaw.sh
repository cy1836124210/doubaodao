#!/system/bin/sh
# IslandBridge dev test: keep the bridge app thawed + relay alive.
LOG=/data/local/tmp/thaw.log
: > $LOG
echo "=== watchdog start $(date) ===" >> $LOG

R=/data/data/com.islandbridge/files/ib_relay.sh
if ps -A 2>/dev/null | grep -q "ib_relay.sh"; then
  echo "relay already running" >> $LOG
else
  rm -f /data/data/com.islandbridge/files/ib_relay.pid
  setsid sh $R </dev/null >>/data/local/tmp/relay.out 2>&1 &
  sleep 2
  echo "relay start -> $(ps -A 2>/dev/null | grep ib_relay.sh | grep -v grep | tr '\n' ' ')" >> $LOG
fi

C=/sys/fs/cgroup/apps/uid_10370
i=0
while [ $i -lt 1000 ]; do
  for f in $(find $C -name cgroup.freeze 2>/dev/null); do
    if [ "$(cat $f 2>/dev/null)" = "1" ]; then
      echo 0 > $f 2>/dev/null && echo "THAW $f $(date +%H:%M:%S)" >> $LOG
    fi
  done
  i=$((i+1))
  sleep 0.3
done
echo "=== watchdog end $(date) ===" >> $LOG
