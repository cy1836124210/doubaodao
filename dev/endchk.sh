#!/system/bin/sh
D=com.larus.nova
echo "### did the reply finish in the Doubao UI? ###"
uiautomator dump /data/local/tmp/g.xml >/dev/null 2>&1
tr '>' '>\n' < /data/local/tmp/g.xml 2>/dev/null |
  grep -oE 'text="[^"]{15,120}"' | tail -5

echo
echo "### module-side: does it log end/finish events? ###"
logcat -d 2>/dev/null | grep -iE "IslandBridge" | grep -iE "end|finish|REPLY_END|onReceiveEnd" | tail -20

echo
echo "### what hook events fired in the Doubao process (last 30) ###"
logcat -d 2>/dev/null | grep -E "\(com.larus.nova\)\[com.islandbridge" | tail -15

echo
echo "### queue file state ###"
QF=/data/data/com.larus.nova/files/ibq.log
ls -l $QF 2>/dev/null
echo "  lines now: $(wc -l < $QF 2>/dev/null)"
echo "  last queued payload types:"
tail -6 $QF 2>/dev/null | while read -r L; do
  echo "$L" | base64 -d 2>/dev/null | grep -oE '"t":"[a-z.]+"' | head -1
done
