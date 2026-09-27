#!/system/bin/sh
APKG=com.islandbridge
echo "### waiting for the real reply to finish ###"
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 4
  S=$(logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -1)
  echo "  t=$((i*4))s  $S"
  case "$S" in *回答完毕*) echo "  => reached 回答完毕"; break ;; esac
done
echo
echo "### final card source labels seen ###"
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -6
echo
echo "### expansion test: open the card and screenshot ###"
input keyevent KEYCODE_HOME; sleep 2
# swipe down from the pill to expand
input swipe 720 60 720 900 400
sleep 3
screencap -p /data/local/tmp/exp.png
echo "  screenshot of expanded card saved"
dumpsys window 2>/dev/null | grep -o 'touchableRegion=SkRegion([^)]*)' | head -3
