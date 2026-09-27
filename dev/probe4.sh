#!/system/bin/sh
# Compare delivery levers. Records what OPLUS decides for each.
L=/data/local/tmp/probe4.log
R=com.islandbridge/.BridgeEventReceiver
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
: > $L
j(){ printf '{"t":"chat.delta","mid":"%s","kind":"text","text":"%s"}' "$1" "$1"; }
b64(){ printf '%s' "$1" | base64 -w0; }
pend(){ dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest com.islandbridge"; }
mark(){
  echo "=== $1  cgroup.freeze=$(cat $CF 2>/dev/null) pending=$(pend)" >> $L
}

mark "T0 start"

# L1: start-foreground-service with the event as an extra
echo "--- L1 start-foreground-service" >> $L
am start-foreground-service -n com.islandbridge/.BridgeService \
   --es evb "$(b64 "$(j SVC1)")" >> $L 2>&1
sleep 4; mark "after L1"

# L2: plain startservice
echo "--- L2 startservice" >> $L
am startservice -n com.islandbridge/.BridgeService >> $L 2>&1
sleep 3; mark "after L2"

# L3: start the activity (known-good control)
echo "--- L3 am start MainActivity" >> $L
am start -n com.islandbridge/.MainActivity >> $L 2>&1
sleep 4; mark "after L3"
am broadcast -a com.islandbridge.EVENT -n $R --ei v 2 --es evb "$(b64 "$(j AFT3)")" >/dev/null 2>&1
sleep 3; mark "after L3 bcast"

# L4: is the app process actually making CPU progress?
PID=$(pidof com.islandbridge | awk '{print $1}')
echo "--- L4 cpu probe pid=$PID" >> $L
awk '{print "  t1 state="$3" utime="$14" stime="$15}' /proc/$PID/stat >> $L 2>&1
sleep 8
awk '{print "  t2 state="$3" utime="$14" stime="$15}' /proc/$PID/stat >> $L 2>&1

echo "--- end $(date +%H:%M:%S)" >> $L
