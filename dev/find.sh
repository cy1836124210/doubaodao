#!/system/bin/sh
D=com.larus.nova
echo "### focus ###"
dumpsys window 2>/dev/null | grep mCurrentFocus

echo
echo "### hook queue (written by the module inside Doubao) ###"
QF=/data/data/com.larus.nova/files/ibq.log
ls -l $QF 2>/dev/null || echo "  (no queue file yet)"
echo "  lines: $(wc -l < $QF 2>/dev/null)"
echo "  tail:"
tail -3 $QF 2>/dev/null | cut -c1-120

echo
echo "### relay worker log ###"
tail -6 /data/local/tmp/islandbridge_relay.log

echo
echo "### is the relay worker alive? ###"
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/relay*|*islandbridge/listen*) echo "  ${d#/proc/}: $c" ;; esac
done

echo
echo "### dump the Doubao UI so we can find the real input box ###"
uiautomator dump /data/local/tmp/d.xml >/dev/null 2>&1
tr '>' '>\n' < /data/local/tmp/d.xml 2>/dev/null |
  grep -oE 'text="[^"]{2,40}"[^>]*bounds="[^"]*"' | head -14
echo
echo "  --- clickable nodes on the lower half ---"
tr '>' '>\n' < /data/local/tmp/d.xml 2>/dev/null |
  grep 'clickable="true"' | grep -oE 'bounds="\[[0-9]+,[0-9]+\]\[[0-9]+,[0-9]+\]"' |
  awk -F'[][,]' '{ if ($5 > 2400) print }' | head -10
