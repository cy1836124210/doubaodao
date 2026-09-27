#!/system/bin/sh
D=com.larus.nova
QF=/data/data/com.larus.nova/files/ibq.log
echo "### focus ###"
dumpsys window 2>/dev/null | grep mCurrentFocus
echo
echo "### input box content now ###"
uiautomator dump /data/local/tmp/e.xml >/dev/null 2>&1
tr '>' '>\n' < /data/local/tmp/e.xml 2>/dev/null | grep 'input_text' | grep -oE 'text="[^"]*"'
echo
echo "### queue file ###"
ls -l $QF 2>/dev/null
echo "  lines: $(wc -l < $QF 2>/dev/null)"
echo
echo "### relay log tail ###"
tail -5 /data/local/tmp/islandbridge_relay.log
echo
echo "### newest Doubao messages (is the reply there?) ###"
tr '>' '>\n' < /data/local/tmp/e.xml 2>/dev/null |
  grep -oE 'text="[^"]{20,90}"' | tail -4
echo
echo "### app alive? ###"
echo "  pid=[$(pidof com.islandbridge)]"
