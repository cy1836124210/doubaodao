#!/system/bin/sh
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
URI=content://com.islandbridge.events

am force-stop $APKG; sleep 3
logcat -c 2>/dev/null

echo "########## send plan.start with a long-running (total=0) card ##########"
EV='{"t":"plan.start","tid":"card1","title":"豆包任务进行中","total":0}'
content call --uri $URI --method event --extra evb:s:"$(echo -n "$EV" | base64 -w0)"
sleep 8

echo
echo "### island protocol ###"
logcat -d 2>/dev/null | grep -iE "AstraIsland" | tail -20
echo
echo "### our app ###"
logcat -d 2>/dev/null | grep -iE "IslandBridge" | tail -15
echo
echo "### freeze state: [$(cat $CF 2>/dev/null)] pid=[$(pidof $APKG)]"
echo
echo "### keep the card visible and screenshot ###"
screencap -p /data/local/tmp/card2.png 2>/dev/null && echo "captured"
# crop the top strip where the island lives
