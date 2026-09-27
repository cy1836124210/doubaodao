#!/system/bin/sh
# CORRECTED channel matrix: the previous provider test hit the *settings* provider (wrong app).
# Now test a binder call INTO our own app, as root.
AUID=10370; APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze
wc_() { for p in $(pidof $APKG 2>/dev/null); do cat /proc/$p/wchan 2>/dev/null; done | head -1; }
show(){ echo "        freeze=$(cat $CF) wchan=$(wc_)"; }

echo "############ 0. Why did a FOREGROUND service still get frozen? ############"
echo "  our process record:"
dumpsys activity processes 2>/dev/null | awk '/\*APP\* UID 10370/{f=1} f&&/mHasForegroundServices|oom adj|curProcState|forcingToImportant|isFrozen|hasStartedServices|Services:/{print "     "$0} f&&/mConnections/{exit}'
echo "  notification importance of our channel:"
dumpsys notification --noredact 2>/dev/null | grep -A3 -i "com.islandbridge" | grep -iE "importance|channel|id=" | head -6

echo
echo "############ 1. BINDER into our own app (correct target) ############"
echo 1 > $CF; sleep 2; echo "  BEFORE:"; show
echo "     calling our own ContentProvider via root..."
su -c "content query --uri content://com.islandbridge.androidx-startup" >/dev/null 2>&1
sleep 2; echo "  AFTER :"; show
echo 0 > $CF; sleep 1

echo
echo "############ 2. BIND an exported SERVICE (bindService => UNFREEZE_REASON_BIND_SERVICE) ############"
echo 1 > $CF; sleep 2; echo "  BEFORE:"; show
am start-service -n com.islandbridge/.BridgeService >/dev/null 2>&1
sleep 2; echo "  AFTER :"; show
echo 0 > $CF; sleep 1

echo
echo "############ 3. Can root just THAW us by writing cgroup.freeze=0 on demand? ############"
echo 1 > $CF; sleep 2; echo "  frozen:  $(show)"
echo 0 > $CF; sleep 1; echo "  thawed:  $(show)"
echo "  -> root CAN toggle it; the question is only WHO toggles it when data arrives."

echo
echo "############ 4. Our app's exported surface (what a pusher could bind) ############"
dumpsys package com.islandbridge 2>/dev/null | sed -n '/Service Resolver Table/,/Provider Resolver Table/p' | head -20

echo
echo "############ 5. SystemUI scope check for our module ############"
grep -ao "([a-z0-9._]*)\[com.islandbridge" /data/adb/lspd/log/modules_*.log 2>/dev/null | sort -u
echo "  ^ if com.android.systemui is ABSENT, our module does NOT run inside the island's process."
