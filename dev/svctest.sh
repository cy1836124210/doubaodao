#!/system/bin/sh
# Does startService reach the app while it is BACKGROUNDED?
# lastStartId increments only when AMS actually delivers onStartCommand.
L=/data/local/tmp/svc.log
: > $L
sid(){ dumpsys activity services com.islandbridge 2>/dev/null | grep -m1 'lastStartId' | tr -d ' '; }
whoami_am(){ echo "  focus=$(dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d ' ')"; }

echo "### baseline: $(sid)" >> $L
whoami_am >> $L

echo "### T1: uid2000 shell am startservice" >> $L
am startservice -n com.islandbridge/.BridgeService --es probe T1 2>&1 | head -3 >> $L
sleep 3; echo "  -> $(sid)" >> $L

echo "### T2: uid0 su am startservice" >> $L
su -c "am startservice -n com.islandbridge/.BridgeService --es probe T2" 2>&1 | head -3 >> $L
sleep 3; echo "  -> $(sid)" >> $L

echo "### T3: uid0 su am start-foreground-service" >> $L
su -c "am start-foreground-service -n com.islandbridge/.BridgeService --es probe T3" 2>&1 | head -3 >> $L
sleep 3; echo "  -> $(sid)" >> $L

echo "### T4: uid0 su cmd activity start-service" >> $L
su -c "cmd activity start-service com.islandbridge/.BridgeService --es probe T4" 2>&1 | head -3 >> $L
sleep 3; echo "  -> $(sid)" >> $L

echo "### T5: control broadcast (expect defer)" >> $L
am broadcast -a com.islandbridge.EVENT -n com.islandbridge/.BridgeEventReceiver --ei v 1 --es ev '{"t":"chat.delta","mid":"SVC_T5","kind":"text","text":"T5"}' 2>&1 | head -3 >> $L
sleep 3
echo "  deferred=$(dumpsys activity broadcasts 2>/dev/null | grep -c 'DEFERRED for manifest com.islandbridge')" >> $L
echo "### end" >> $L
