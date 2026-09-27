#!/system/bin/sh
# Is com.islandbridge marked virtualFreeze=true by OPPO's ext layer?
# virtualFreeze (not raw cgroup.freeze) is what DEFER_BY_OPLUS keys off.
O=/data/local/tmp/vf.txt
: > $O

echo "### islandbridge ProcessRecordExtImpl ###" >> $O
dumpsys activity processes 2>/dev/null | awk '
/\*APP\* UID 10370/ {f=1}
f {print}
f && /ProcessRecordExtImpl/ {c++; if(c>=1) exit}
' >> $O

echo "" >> $O
echo "### full record block for our proc (60 lines) ###" >> $O
dumpsys activity processes 2>/dev/null | awk '/\*APP\* UID 10370/{f=1} f{print; n++} n>55{exit}' >> $O

echo "" >> $O
echo "### every virtualFreeze: true and its owner ###" >> $O
dumpsys activity processes 2>/dev/null | awk '
/^\s+\*APP\*/ {app=$0}
/virtualFreeze: true/ {print "  " app "  <<< " $0}
' | head -20 >> $O

echo "" >> $O
echo "### current deferred queue entries ###" >> $O
dumpsys activity broadcasts 2>/dev/null | grep -E 'not runnable because|DEFERRED for' | head -20 >> $O

cat $O
