#!/system/bin/sh
# Try adding com.islandbridge to ColorOS "not restricted" whitelists.
B=/data/oplus/os/battery
BAK=/data/local/tmp/oplusbak
mkdir -p $BAK
for f in not_restrict.xml startinfo_white.xml notify_whitelist.xml; do
  [ -f $B/$f ] && cp -a $B/$f $BAK/$f.bak
done
echo "=== before ==="
for f in not_restrict.xml startinfo_white.xml notify_whitelist.xml; do
  echo "  $f islandbridge=$(grep -c islandbridge $B/$f 2>/dev/null)"
done
echo "=== insert ==="
for f in not_restrict.xml startinfo_white.xml notify_whitelist.xml; do
  if [ -f $B/$f ] && ! grep -q islandbridge $B/$f; then
    sed -i 's#</gs>#<p att="com.islandbridge" /></gs>#' $B/$f
  fi
  echo "  $f now=$(grep -c islandbridge $B/$f 2>/dev/null) size=$(wc -c < $B/$f 2>/dev/null)"
done
echo "=== also sys_ams_skipbroadcast ==="
S=/data/oplus/os/config/sys_ams_skipbroadcast.xml
[ -f $S ] && echo "  exists: $(wc -c < $S)" && cp -a $S $BAK/ 2>/dev/null
echo "=== startup lists ==="
ls /data/oplus/os/startup/ 2>/dev/null
echo "=== done, waiting 5s to see if system rewrites ==="
sleep 5
for f in not_restrict.xml startinfo_white.xml notify_whitelist.xml; do
  echo "  after5s $f islandbridge=$(grep -c islandbridge $B/$f 2>/dev/null) size=$(wc -c < $B/$f 2>/dev/null)"
done
