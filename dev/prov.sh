#!/system/bin/sh
AUID=10370; APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze
wc_() { for p in $(pidof $APKG 2>/dev/null); do cat /proc/$p/wchan 2>/dev/null; done | head -1; }
show(){ echo "        freeze=$(cat $CF) wchan=$(wc_)"; }

echo "########## 1. content CLI: does it support call? ##########"
content help 2>&1 | head -30

echo
echo "########## 2. Does 'content call' thaw a frozen app? (binder txn) ##########"
echo 1 > $CF; sleep 2; echo "  frozen:"; show
echo "     -> content call on our app's own provider record"
content call --uri content://com.islandbridge.androidx-startup --method probe 2>&1 | head -3
sleep 2; echo "  after:"; show
echo 0 > $CF; sleep 1

echo
echo "########## 3. Same via 'content query' for comparison ##########"
echo 1 > $CF; sleep 2; echo "  frozen:"; show
content query --uri content://com.islandbridge.androidx-startup 2>&1 | head -2
sleep 2; echo "  after:"; show
echo 0 > $CF; sleep 1

echo
echo "########## 4. Binder from SystemUI's uid? check who can reach us ##########"
echo "  our providers (current):"
dumpsys activity providers 2>/dev/null | grep -A3 "com.islandbridge" | head -15

echo
echo "########## 5. Does a frozen app's ContentProvider still RESPOND? ##########"
echo "  (thaw then query — measure) "
echo 1 > $CF; sleep 2
t0=$(date +%s%N)
content query --uri content://com.islandbridge.androidx-startup >/dev/null 2>&1
t1=$(date +%s%N)
echo "     round trip: $(( (t1-t0)/1000000 )) ms"
echo 0 > $CF
