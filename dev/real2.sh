#!/system/bin/sh
D=com.larus.nova
APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze

echo "### launch Doubao ###"
monkey -p $D -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep 12
echo "  doubao pid=[$(pidof $D)]"
echo "  hooks: $(logcat -d 2>/dev/null | grep -c 'IslandBridge hooked')"

# make sure our app is DEAD so the wake is a real test
am force-stop $APKG
sleep 2
logcat -c 2>/dev/null
echo "  app killed: pid=[$(pidof $APKG)]"

echo
echo "### type + send a real prompt ###"
input tap 632 2976
sleep 2
input text "hello"
sleep 2
input tap 1304 3008
echo "  sent"

for i in 1 2 3 4 5 6 7 8; do
  sleep 4
  echo "  t=$((i*4))s pid=[$(pidof $APKG)] freeze=[$(cat $CF 2>/dev/null)]"
done

echo
echo "### what source label did the REAL Doubao path produce? ###"
logcat -d 2>/dev/null | grep -oE '岛card src=[^ ]* st=[^ ]* body=[0-9]+字' | tail -10
echo
echo "### full pipeline ###"
logcat -d 2>/dev/null | grep "IslandBridge" | tail -12
