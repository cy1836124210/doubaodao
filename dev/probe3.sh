#!/system/bin/sh
# Which lever actually thaws com.islandbridge on ColorOS?
L=/data/local/tmp/probe3.log
R=com.islandbridge/.BridgeEventReceiver
CF=/sys/fs/cgroup/apps/uid_10370/cgroup.freeze
: > $L
j(){ printf '{"t":"chat.delta","mid":"%s","kind":"text","text":"%s"}' "$1" "$1"; }
b64(){ printf '%s' "$1" | base64 -w0; }
st(){
  echo "  cgroup.freeze=$(cat $CF 2>/dev/null)" >> $L
  dumpsys activity processes com.islandbridge 2>/dev/null | grep -m1 'isFrozen=' >> $L
}
pend(){ dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest com.islandbridge"; }
bcast(){ am broadcast -a com.islandbridge.EVENT -n $R --ei v 2 --es evb "$(b64 "$(j $1)")" >/dev/null 2>&1; }

echo "=== T0 baseline ===" >> $L; st; echo "  pending=$(pend)" >> $L

echo "=== T1 plain broadcast ===" >> $L
bcast VAR_A; sleep 3; st; echo "  pending=$(pend)" >> $L

echo "=== T2 am unfreeze + immediate broadcast ===" >> $L
am unfreeze com.islandbridge >/dev/null 2>&1; bcast VAR_B; sleep 3; st; echo "  pending=$(pend)" >> $L

echo "=== T3 cached_apps_freezer=disabled + broadcast ===" >> $L
settings put global cached_apps_freezer disabled >/dev/null 2>&1; sleep 1
bcast VAR_C; sleep 3; st; echo "  pending=$(pend)" >> $L
settings put global cached_apps_freezer device_default >/dev/null 2>&1

echo "=== T4 wake via KeepAliveReceiver + broadcast ===" >> $L
am broadcast -a com.islandbridge.KEEPALIVE -n com.islandbridge/.KeepAliveReceiver >/dev/null 2>&1
sleep 2; bcast VAR_D; sleep 3; st; echo "  pending=$(pend)" >> $L

echo "=== T5 manual cgroup thaw + broadcast ===" >> $L
echo 0 > $CF 2>/dev/null; bcast VAR_E; sleep 3; st; echo "  pending=$(pend)" >> $L

echo "=== end ===" >> $L
