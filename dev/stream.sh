#!/system/bin/sh
APKG=com.islandbridge
AUID=10370
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze
URI=content://com.islandbridge.events

echo "########## STREAMING TEST: 30 rapid deltas into a frozen app ##########"
am force-stop $APKG; sleep 3
echo "  app killed: pid=[$(pidof $APKG)]"

# let it start + bind
content call --uri $URI --method event --extra evb:s:"$(echo -n '{"t":"plan.start","tid":"stream1","title":"STREAM TEST","total":30}' | base64 -w0)" >/dev/null
sleep 5
echo "  after start: pid=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)]"

logcat -c 2>/dev/null
T0=$(date +%s%N)
i=1
OK=0; FAIL=0
while [ $i -le 30 ]; do
    EV="{\"t\":\"plan.progress\",\"tid\":\"stream1\",\"done\":$i,\"total\":30,\"text\":\"step $i\"}"
    B64=$(echo -n "$EV" | base64 -w0)
    OUT=$(content call --uri $URI --method event --extra evb:s:"$B64" 2>/dev/null)
    case "$OUT" in *ok=true*) OK=$((OK+1));; *) FAIL=$((FAIL+1));; esac
    i=$((i+1))
done
T1=$(date +%s%N)
echo "  sent 30 deltas: ok=$OK fail=$FAIL  total=$(( (T1-T0)/1000000 ))ms  avg=$(( (T1-T0)/1000000/30 ))ms/call"
echo "  freeze state after stream: [$(cat $CF 2>/dev/null)] pid=[$(pidof $APKG)]"

echo
echo "  how many actually reached the app pipeline?"
logcat -d 2>/dev/null | grep -c "ev ok plan.progress"
echo "  (30 = perfect, 0 = all lost)"

echo
echo "########## Screenshot to see the island card ##########"
screencap -p /data/local/tmp/island.png 2>/dev/null && echo "  captured" || echo "  screencap failed"
