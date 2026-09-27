#!/system/bin/sh
APKG=com.islandbridge
OUT=/data/local/tmp/life2.log
echo "### waiting for chat.end / 回答完毕 ###"
for i in $(seq 1 20); do
  sleep 3
  E=$(grep -c 'ev ok chat.end' $OUT 2>/dev/null)
  D=$(grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | tail -1)
  echo "  t=$((i*3))s chat.end=$E | $D"
  case "$D" in *回答完毕*) echo "  *** 回答完毕 REACHED ***"; break ;; esac
done
echo
echo "### final distinct states ###"
grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' $OUT 2>/dev/null | uniq | tail -8
echo
echo "### pill is showing status only (no body) — confirm last compact payload ###"
grep -oE 'st=[^ ]*' $OUT 2>/dev/null | tail -3
echo
echo "### events ###"
grep -oE 'ev ok (chat|plan)\.[a-z]+' $OUT 2>/dev/null | sort | uniq -c
