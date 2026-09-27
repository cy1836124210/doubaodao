#!/system/bin/sh
echo "########## toybox nc -L: persistent server mode ##########"
rm -f /data/local/tmp/L.log
/system/bin/nc -L -p 8897 >/data/local/tmp/L.log 2>&1 &
LP=$!
sleep 1
i=1
while [ $i -le 6 ]; do
  printf 'line%s\n' $i | /system/bin/nc 127.0.0.1 8897
  i=$((i+1))
done
sleep 2
echo "  received $(wc -l < /data/local/tmp/L.log) lines:"
cat /data/local/tmp/L.log
echo "  server still alive: $([ -d /proc/$LP ] && echo YES || echo NO)"
kill -9 $LP 2>/dev/null
pkill -f "nc -L -p 8897" 2>/dev/null

echo
echo "########## throughput: 10 sequential content calls ##########"
APKG=com.islandbridge
URI=content://com.islandbridge.events
am force-stop $APKG; sleep 2
content call --uri $URI --method ping >/dev/null 2>&1
sleep 3
T0=$(date +%s%N)
i=1
while [ $i -le 10 ]; do
  B=$(echo -n "{\"t\":\"chat.delta\",\"cid\":\"c\",\"mid\":\"m\",\"kind\":\"text\",\"text\":\"x$i\"}" | base64 -w0)
  content call --uri $URI --method event --extra evb:s:"$B" >/dev/null 2>&1
  i=$((i+1))
done
T1=$(date +%s%N)
echo "  10 content calls: $(( (T1-T0)/1000000 ))ms  -> avg $(( (T1-T0)/1000000/10 ))ms/call"
echo "  (note: date has 1s resolution here, treat as approximate)"
