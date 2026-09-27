#!/system/bin/sh
# Multi-strategy background delivery probe.
L=/data/local/tmp/probe.log
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
: > $L
b64(){ printf '%s' "$1" | base64 -w0; }
j(){ printf '{"t":"chat.delta","mid":"%s","kind":"text","text":"%s"}' "$1" "$1"; }
snap(){ echo "[$(date +%H:%M:%S)] $1 | pid=$(pidof com.islandbridge) freeze=$(cat $CF 2>/dev/null)" >> $L; }
bcast(){ am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
   --ei v 2 --es evb "$(b64 "$(j $1)")" >> $L 2>&1; }

snap "START"
echo "--- A: plain explicit v=2" >> $L;  bcast VAR_A; sleep 3
snap "after A"

echo "--- B: implicit EVENT_RELAY (uid-1000 sys_server path)" >> $L
am broadcast -a com.islandbridge.EVENT_RELAY --es ev "$(j VAR_B)" >> $L 2>&1
sleep 3; snap "after B"

echo "--- C: explicit v=1 raw ev" >> $L
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
   --ei v 1 --es ev "$(j VAR_C)" >> $L 2>&1
sleep 3; snap "after C"

echo "--- D: am unfreeze then broadcast" >> $L
am unfreeze com.islandbridge >> $L 2>&1
sleep 1; snap "after unfreeze"
bcast VAR_D; sleep 3; snap "after D"

echo "--- E: start-foreground-service then broadcast" >> $L
am start-foreground-service -n com.islandbridge/.BridgeService >> $L 2>&1
sleep 2; snap "after start-fgs"
bcast VAR_E; sleep 3; snap "after E"

snap "END"
