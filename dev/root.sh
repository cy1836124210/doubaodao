#!/system/bin/sh
echo "### which root solution? ###"
for p in /data/adb/ksu /data/adb/magisk /data/adb/ksud /data/adb/ap /data/adb/andro /data/adb/kernel-su; do
  [ -e "$p" ] && echo "  EXISTS: $p"
done
echo "  ksud      : $(which ksud 2>/dev/null) $(ksud -V 2>&1 | head -1)"
echo "  magisk    : $(which magisk 2>/dev/null) $(magisk -V 2>&1 | head -1)"
echo "  su        : $(which su 2>/dev/null)"
echo "  /data/adb contents:"; ls /data/adb/ 2>/dev/null

echo
echo "### service.d support ###"
echo "  /data/adb/service.d: $(ls -la /data/adb/service.d/ 2>/dev/null | tail -n +2 | tr '\n' '|')"
echo "  post-fs-data.d:      $(ls /data/adb/post-fs-data.d/ 2>/dev/null | tr '\n' ' ')"

echo
echo "### modules dir ###"
ls -d /data/adb/modules/*/ 2>/dev/null | head -20

echo
echo "### did anything log our boot script? ###"
logcat -d 2>/dev/null | grep -iE "service.d|islandbridge.sh|ksud.*service" | tail -5

echo
echo "### SELinux for our spawn attempt ###"
logcat -d 2>/dev/null | grep -iE "avc.*denied" | grep -iE "islandbridge|ib_relay" | tail -5
