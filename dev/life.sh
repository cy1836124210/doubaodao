#!/system/bin/sh
# Full lifecycle capture with a continuous logcat to file (immune to ring rotation)
D=com.larus.nova
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
OUT=/data/local/tmp/life.log

monkey -p $D -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 10
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null
logcat -v time -s IslandBridge:* > $OUT 2>&1 &
LP=$!
sleep 1
echo "  app killed: pid=[$(pidof $APKG)]  doubao=[$(pidof $D)]"

# clear input, type, send
input tap 632 1740; sleep 1
input keyevent KEYCODE_MOVE_END
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do input keyevent KEYCODE_DEL; done
sleep 1
input text "write a 200 word essay about autumn"
sleep 2
input tap 1330 1745
echo "  sent"

for i in $(seq 1 24); do
  sleep 3
  S=$(grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | tail -1)
  echo "  t=$((i*3))s freeze=[$(cat $CF 2>/dev/null)] $S"
  case "$S" in *回答完毕*) echo "  *** 回答完毕 reached ***"; break ;; esac
done

kill -9 $LP 2>/dev/null
echo
echo "===== lifecycle: every distinct state in order ====="
grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | uniq | head -20
echo
echo "===== body length over time (proves newest-segment streaming) ====="
grep -oE 'body=[0-9]+字' $OUT 2>/dev/null | uniq | tr '\n' ' '
echo
echo "===== event types delivered ====="
grep -oE 'ev ok (chat|plan)\.[a-z]+' $OUT 2>/dev/null | sort | uniq -c
