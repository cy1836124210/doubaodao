#!/system/bin/sh
# Real Doubao lifecycle, with correct input-text escaping (spaces -> %s)
D=com.larus.nova
APKG=com.islandbridge
OUT=/data/local/tmp/life2.log

monkey -p $D -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 10
am force-stop $APKG; sleep 2
logcat -c 2>/dev/null
logcat -v time -s IslandBridge:* > $OUT 2>&1 &
LP=$!
sleep 1
echo "  app dead: pid=[$(pidof $APKG)]"

input tap 632 1744
sleep 2
# clear whatever is there
input keyevent KEYCODE_MOVE_END
for i in $(seq 1 30); do input keyevent KEYCODE_DEL; done
sleep 1
# spaces must be %s for `input text`
input text "写一段关于秋天的短文"
sleep 2
echo "  typed; input box now:"
uiautomator dump /data/local/tmp/f.xml >/dev/null 2>&1
tr '>' '>\n' < /data/local/tmp/f.xml 2>/dev/null | grep 'input_text' | grep -oE 'text="[^"]*"'
input tap 1330 1745
echo "  tapped send"

for i in $(seq 1 20); do
  sleep 3
  S=$(grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | tail -1)
  echo "  t=$((i*3))s $S"
  case "$S" in *回答完毕*) echo "  *** 回答完毕 ***"; break ;; esac
done
kill -9 $LP 2>/dev/null

echo
echo "===== distinct lifecycle states (in order) ====="
grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | uniq
echo
echo "===== body sizes over time ====="
grep -oE 'body=[0-9]+字' $OUT 2>/dev/null | uniq | tr '\n' ' '
echo
echo "===== delivered events ====="
grep -oE 'ev ok (chat|plan)\.[a-z]+' $OUT 2>/dev/null | sort | uniq -c
