#!/system/bin/sh
# Test the simple root levers for "don't freeze com.islandbridge"
L=/data/local/tmp/levers.log
R=com.islandbridge/.BridgeEventReceiver
: > $L
j(){ printf '{"t":"chat.delta","mid":"%s","kind":"text","text":"%s"}' "$1" "$1"; }
b64(){ printf '%s' "$1" | base64 -w0; }
pend(){ dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest com.islandbridge"; }
hz(){ dumpsys oplus.hans.IHansComunication 2>/dev/null | grep -c "10370.*Freeze: true"; }

echo "### baseline pending=$(pend)" >> $L

echo "### L1: oplus_freeze shell cmds" >> $L
for c in "app-freeze config" "app-freeze stats" "app-freeze syn"; do
  echo "--- cmd oplus_freeze $c" >> $L
  cmd oplus_freeze $c 2>&1 | head -6 >> $L
done

echo "### L2: am freeze/unfreeze --sticky variants" >> $L
am freeze --help 2>&1 | head -8 >> $L
am unfreeze --sticky com.islandbridge 2>&1 >> $L
sleep 2
am unfreeze com.islandbridge 2>&1 >> $L

echo "### L3: recent_lock.xml (ColorOS 锁定后台)" >> $L
F=/data/oplus/os/battery/recent_lock.xml
echo "  before: $(cat $F)" >> $L
cp -a $F /data/local/tmp/recent_lock.bak 2>/dev/null
printf '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?><gs><p att="com.islandbridge" /></gs>' > $F
echo "  after: $(cat $F)" >> $L

echo "### L4: send broadcast now (post-unfreeze)" >> $L
am broadcast -a com.islandbridge.EVENT -n $R --ei v 2 --es evb "$(b64 "$(j LVR1)")" >/dev/null 2>&1
sleep 3; echo "  pending=$(pend)" >> $L

echo "### L5: force-stop + restart service then broadcast" >> $L
am startservice -n com.islandbridge/.BridgeService >/dev/null 2>&1
sleep 2
am broadcast -a com.islandbridge.EVENT -n $R --ei v 2 --es evb "$(b64 "$(j LVR2)")" >/dev/null 2>&1
sleep 3; echo "  pending=$(pend)" >> $L

echo "### L6: does OPPO re-freeze us?" >> $L
sleep 20
echo "  pending=$(pend)" >> $L
dumpsys activity processes com.islandbridge 2>/dev/null | grep -m1 'isFrozen=' >> $L

echo "### end" >> $L
