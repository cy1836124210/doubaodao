#!/system/bin/sh
# Clean full-cycle real-Doubao verification.
# No STOP actions, fresh app process, continuous capture, generous timeout.
D=com.larus.nova
APKG=com.islandbridge
OUT=/data/local/tmp/final2.log
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze

am force-stop $APKG; sleep 2
: > /data/data/com.larus.nova/files/ibq.log.proc 2>/dev/null
logcat -c 2>/dev/null
logcat -v time -s IslandBridge:* > $OUT 2>&1 &
LP=$!
sleep 1
echo "  app dead pid=[$(pidof $APKG)]  freeze=[$(cat $CF 2>/dev/null)]"

monkey -p $D -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 8

input tap 632 1744; sleep 2
input keyevent KEYCODE_MOVE_END
for i in $(seq 1 40); do input keyevent KEYCODE_DEL; done
sleep 1
input text "讲一个关于星星的短故事"
sleep 2
input tap 1330 1745
echo "  prompt sent"

DONE=0
for i in $(seq 1 40); do
  sleep 4
  S=$(grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | tail -1)
  echo "  t=$((i*4))s freeze=[$(cat $CF 2>/dev/null)] $S"
  case "$S" in *回答完毕*) DONE=1; echo "  *** 回答完毕 REACHED ***"; break ;; esac
done
kill -9 $LP 2>/dev/null

echo
echo "===== lifecycle (distinct states, in order) ====="
grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | uniq
echo
echo "===== delivered events ====="
grep -oE 'ev ok (chat|plan)\.[a-z]+' $OUT 2>/dev/null | sort | uniq -c
echo
echo "===== did we reach 回答完毕? $DONE ====="
