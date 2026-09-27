#!/system/bin/sh
# THE decisive test: is the block at the BROADCAST QUEUE (app-level) or the KERNEL freezer?
# freeze_binder_enabled=true  ->  binder transactions thaw a frozen process, broadcasts do not.

AUID=10370
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze

wchan() { for p in $(pidof $APKG 2>/dev/null); do echo "   pid $p: $(cat /proc/$p/wchan 2>/dev/null)"; done; }
defer() { dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest $APKG"; }

echo "=== step 1: force-freeze our uid the same way ColorOS does ==="
echo 1 > $CF 2>/dev/null
echo "   cgroup.freeze=$(cat $CF)"
sleep 2
echo "   kernel state (expect do_freezer_trap):"
wchan
D0=$(defer); echo "   deferred_before=$D0"

echo
echo "=== step 2: deliver a BROADCAST while frozen ==="
am broadcast -a com.islandbridge.KEEPALIVE -n $APKG/.KeepAliveReceiver >/dev/null 2>&1
sleep 4
D1=$(defer)
echo "   deferred_after=$D1   (delta=$((D1-D0)))"
echo "   still frozen?  cgroup.freeze=$(cat $CF)"
wchan

echo
echo "=== step 3: deliver a BINDER call (content provider query) while frozen ==="
echo "   -> binder into the app, kernel should thaw it (freeze_binder_enabled=true)"
content query --uri content://$APKG.androidx-startup 2>&1 | head -5
sleep 2
echo "   after binder:  cgroup.freeze=$(cat $CF)"
wchan

echo
echo "=== step 4: can a broadcast now get through? ==="
D2=$(defer)
am broadcast -a com.islandbridge.KEEPALIVE -n $APKG/.KeepAliveReceiver >/dev/null 2>&1
sleep 4
D3=$(defer)
echo "   deferred delta=$((D3-D2))"

echo
echo "=== step 5: unfreeze, restore ==="
echo 0 > $CF 2>/dev/null
sleep 2
echo "   cgroup.freeze=$(cat $CF)"
wchan

echo
echo "=== what actually ran? ==="
logcat -d -t 60 2>/dev/null | grep -iE "islandbridge|KeepAlive|Freezer|freez" | tail -20
