#!/system/bin/sh
# Controlled experiment: does cgroup freeze cause event deferral?
# phase1: force-freeze the app cgroup, then broadcast an event.
# phase2: thaw, then broadcast a 3-event chat sequence.
# If freeze is the culprit, only phase2's events reach the app.
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
L=/data/local/tmp/freezetest.log
FZ="$1"; T1="$2"; T2="$3"; T3="$4"
: > $L

echo "baseline freeze=$(cat $CF 2>/dev/null)" >> $L

echo "== phase1: FORCED FROZEN ==" >> $L
echo 1 > $CF 2>/dev/null
sleep 2
echo "freeze=$(cat $CF 2>/dev/null)" >> $L
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
    --ei v 2 --es evb "$FZ" >> $L 2>&1
sleep 4
echo "after_bcast freeze=$(cat $CF 2>/dev/null)" >> $L

echo "== phase2: THAWED ==" >> $L
echo 0 > $CF 2>/dev/null
sleep 2
echo "freeze=$(cat $CF 2>/dev/null)" >> $L
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
    --ei v 2 --es evb "$T1" >> $L 2>&1
sleep 1
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
    --ei v 2 --es evb "$T2" >> $L 2>&1
sleep 1
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver \
    --ei v 2 --es evb "$T3" >> $L 2>&1
sleep 3
echo "after_bcast freeze=$(cat $CF 2>/dev/null)" >> $L
echo "== done ==" >> $L
