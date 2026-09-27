#!/system/bin/sh
# Which delivery channels penetrate the ColorOS freezer?
echo "########## A. Is WeChat on OPPO's do-not-freeze / battery whitelists? ##########"
for f in /data/oplus/os/battery/not_restrict.xml /data/oplus/os/battery/doze_wl_local.xml /data/oplus/os/battery/bpm/not_restrict.xml; do
  if [ -f "$f" ]; then
    echo "--- $f ($(wc -c < $f) bytes) ---"
    echo "   tencent.mm : $(grep -c 'com.tencent.mm' $f 2>/dev/null)"
    echo "   larus.nova : $(grep -c 'com.larus.nova' $f 2>/dev/null)"
    echo "   islandbridge: $(grep -c 'com.islandbridge' $f 2>/dev/null)"
  fi
done
echo
echo "--- search ALL of /data/oplus/os for our app vs wechat ---"
for p in com.tencent.mm com.larus.nova com.islandbridge com.astraflow.tool; do
  n=$(grep -rl "$p" /data/oplus/os 2>/dev/null | wc -l)
  echo "$p appears in $n files under /data/oplus/os"
done
echo
echo "--- which files whitelist wechat but NOT us? ---"
for f in $(grep -rl 'com.tencent.mm' /data/oplus/os 2>/dev/null | head -12); do
  echo "  $f  | us: $(grep -c 'com.islandbridge' $f 2>/dev/null) | doubao: $(grep -c 'com.larus.nova' $f 2>/dev/null)"
done

echo
echo "########## B. Kernel freezer + binder thaw support ##########"
echo "--- freezer modules ---"
ls /sys/module 2>/dev/null | grep -iE "freez|hans|binder" 
echo "--- freezer binder params ---"
for d in /sys/module/*freez*/parameters /sys/module/*hans*/parameters; do
  [ -d "$d" ] && { echo "  $d:"; ls $d 2>/dev/null | sed 's/^/     /'; }
done
echo "--- freezer-binder sysfs knobs anywhere ---"
find /sys -maxdepth 4 -iname "*freez*binder*" 2>/dev/null | head
find /sys -maxdepth 4 -iname "*binder*freez*" 2>/dev/null | head

echo
echo "########## C. Delivery-channel matrix: what the framework defers ##########"
echo "--- our app's CURRENT process state ---"
dumpsys activity processes 2>/dev/null | awk '/\*APP\* UID 10370/{f=1} f&&/isFreezeExempt|isFrozen|cached=|curProcState|mHasForegroundServices|notResponding/{print "   "$0} f&&/^$/{c++; if(c>0)exit}'

echo
echo "--- live deferred-broadcast reason for our app ---"
dumpsys activity broadcasts 2>/dev/null | grep -A3 "9030:com.islandbridge" | head -12

echo
echo "--- freezer settings (binder thaw levers) ---"
dumpsys activity 2>/dev/null | sed -n '/Freezer settings/,/^$/p' | head -15

echo
echo "########## D. Confirm frozen processes really are parked ##########"
ps -A -o USER,PID,STAT,WCHAN,NAME 2>/dev/null | grep -E "tencent.mm|islandbridge|larus" | head -10
