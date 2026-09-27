#!/system/bin/sh
# Test the real OPPO freeze levers with broadcast verification.
L=/data/local/tmp/levers.log
R=com.islandbridge/.BridgeEventReceiver
: > $L
j(){ printf '{"t":"chat.delta","mid":"%s","kind":"text","text":"%s"}' "$1" "$1"; }
b64(){ printf '%s' "$1" | base64 -w0; }
pend(){ dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest com.islandbridge"; }
fz(){ dumpsys activity processes com.islandbridge 2>/dev/null | grep -m1 'isFrozen=' | tr -d ' '; }
try(){
  echo "--- $1" >> $L
  am broadcast -a com.islandbridge.EVENT -n $R --ei v 2 --es evb "$(b64 "$(j $2)")" >/dev/null 2>&1
  sleep 3
  echo "    pending=$(pend) $(fz)" >> $L
}

echo "### base pending=$(pend) $(fz)" >> $L

echo "### A: dumpsys oplus_freeze app-freeze config" >> $L
dumpsys oplus_freeze app-freeze config 2>&1 | head -25 >> $L
echo "### A2: app-freeze syn" >> $L
dumpsys oplus_freeze app-freeze syn 2>&1 | head -20 >> $L

echo "### B: set-config disable freeze for uid 10370" >> $L
dumpsys oplus_freeze app-freeze set-config 0 10370 0 2>&1 | head -5 >> $L
sleep 2
try "B after set-config 0 10370 0" LVR_B

echo "### C: key_proc.xml (never-freeze list)" >> $L
K=/data/oplus/os/bpm/key_proc.xml
echo "  before: $(cat $K)" >> $L
cp -a $K /data/local/tmp/key_proc.bak 2>/dev/null
cat > $K <<'EOF'
<?xml version='1.0' encoding='utf-8' standalone='yes' ?><gs><p att="com.tencent.mm#com.tencent.mm:push" /><p att="com.tencent.mobileqq#com.tencent.mobileqq:MSF" /><p att="com.islandbridge#com.islandbridge" /></gs>
EOF
echo "  after: $(cat $K)" >> $L

echo "### D: bpm.xml (background not restricted)" >> $L
B=/data/oplus/os/bpm/bpm.xml
cp -a $B /data/local/tmp/bpm.bak 2>/dev/null
sed -i 's#</gs>#<p att="com.islandbridge" /></gs>#' $B
echo "  islandbridge in bpm.xml: $(grep -c islandbridge $B)" >> $L

echo "### E: wait 15s for OPPO to re-evaluate, then broadcast" >> $L
sleep 15
try "E after whitelist edits" LVR_E
sleep 10
try "E2 still alive?" LVR_E2

echo "### end $(date +%H:%M:%S)" >> $L
