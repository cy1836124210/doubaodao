#!/system/bin/sh
# KernelSU service.d marker — proves boot execution and records the env.
LOG=/data/local/tmp/marker.log
{
  echo "=== $(date) ==="
  echo "pid=$$ uid=$(id -u) context=$(cat /proc/self/attr/current 2>/dev/null)"
  echo "boot_completed=$(getprop sys.boot_completed) sys.boot_from=$(getprop sys.boot_completed)"
  echo "PATH=$PATH"
} >> "$LOG" 2>&1

# start the two long-lived helpers, detached from this boot-time shell
pkill -f ib_relay.sh 2>/dev/null
pkill -f ib_listen.sh 2>/dev/null
sleep 1
setsid sh /data/adb/service.d/islandbridge_relay.sh </dev/null >>/data/local/tmp/relay.log 2>&1 &
echo "relay spawned pid=$!" >> "$LOG" 2>&1
setsid sh /data/adb/service.d/islandbridge_listen.sh </dev/null >>/data/local/tmp/relay.log 2>&1 &
echo "listener spawned pid=$!" >> "$LOG" 2>&1
