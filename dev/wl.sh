#!/system/bin/sh
echo "### OPLUS freeze/hans whitelist files ###"
for d in /data/system/oplus /data/oplus /data/system/hans /data/vendor/oplus; do
  [ -d "$d" ] && { echo "-- $d --"; ls -la "$d" 2>/dev/null | head -20; }
done

echo
echo "### any freeze-whitelist-ish file anywhere in /data/system ###"
find /data/system -maxdepth 3 -iname "*freez*" -o -maxdepth 3 -iname "*hans*" 2>/dev/null | head -20

echo
echo "### settings keys mentioning freeze/hans/whitelist ###"
settings list system 2>/dev/null | grep -iE "freez|hans|whitelist|protected|doze" | head -20

echo
echo "### noactive installed state + is it the freezer killer? ###"
dumpsys package cn.myflv.noactive 2>/dev/null | grep -iE "versionName|enabled=|codePath" | head -5

echo
echo "### memory cgroup groups (OPLUS placement) ###"
echo "ours:   $(grep memory /proc/$(pidof com.islandbridge)/cgroup 2>/dev/null)"
echo "systemui: $(grep memory /proc/$(pidof com.android.systemui)/cgroup 2>/dev/null)"

echo
echo "### is there a writable 'active' list we can add to? ###"
ls -la /sys/fs/cgroup/apps/ 2>/dev/null | head -15
