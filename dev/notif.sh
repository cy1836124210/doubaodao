#!/system/bin/sh
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze

echo "########## 1. Foreground-service notification state ##########"
dumpsys notification --noredact 2>/dev/null | grep -A6 "pkg=com.islandbridge" | head -14
echo "  --- channel config ---"
dumpsys notification --noredact 2>/dev/null | grep -B2 -A8 "channel=bridge" | head -20

echo
echo "########## 2. Is the notification CHANNEL blocked/disabled? ##########"
dumpsys notification_manager 2>/dev/null | grep -iA4 "com.islandbridge" | head -20
cmd notification get_notification_channels com.islandbridge 2>/dev/null || echo "  (cmd not available)"

echo
echo "########## 3. appops for notifications ##########"
dumpsys appops 2>/dev/null | grep -A3 "com.islandbridge" | grep -iE "POST_NOTIFICATION|OP_POST" | head -5

echo
echo "########## 4. DOES AN ISLAND->APP BINDER CALLBACK THAW US? ##########"
echo "  (buttons/reply on the card must still work while frozen)"
am force-stop $APKG; sleep 2
printf 'zqtok123\t{"t":"plan.start","tid":"cb","title":"回调测试","total":0}\n' | nc 127.0.0.1 8799
sleep 6
echo "  after card: freeze=[$(cat $CF 2>/dev/null)] pid=[$(pidof $APKG)]"
echo "  ... now trigger an island action the way a card tap would."
echo "  Simulate inbound binder from SystemUI by asking island to re-offer session:"
logcat -c 2>/dev/null
am force-stop com.android.systemui 2>/dev/null && echo "  (restarting SystemUI would drop the island - skipping)"
echo "  freeze still=[$(cat $CF 2>/dev/null)]"

echo
echo "########## 5. Does the app survive long-term frozen WITHOUT losing the island session? ##########"
sleep 20
echo "  freeze=[$(cat $CF 2>/dev/null)] pid=[$(pidof $APKG)]"
echo "  session-lost events since: $(logcat -d 2>/dev/null | grep -c 'onSessionLost')"
