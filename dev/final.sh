#!/system/bin/sh
AUID=10370; APKG=com.islandbridge
CF=/sys/fs/cgroup/apps/uid_$AUID/cgroup.freeze
wc_() { for p in $(pidof $APKG 2>/dev/null); do cat /proc/$p/wchan 2>/dev/null; done | head -1; }
snap(){ echo "        freeze=$(cat $CF) wchan=$(wc_)"; }

echo "########## 1. not_restrict.xml — REAL entries? (load-bearing) ##########"
echo "  our app as a real entry : [$(grep -o 'att="com.islandbridge"' /data/oplus/os/battery/not_restrict.xml 2>/dev/null)]"
echo "  wechat as a real entry  : [$(grep -o 'att="com.tencent.mm"' /data/oplus/os/battery/not_restrict.xml 2>/dev/null)]"
echo "  raw substring count ours: $(grep -c 'com.islandbridge' /data/oplus/os/battery/not_restrict.xml 2>/dev/null)"
echo "  context of our substring:"
grep -o -E '.{60}com\.islandbridge.{60}' /data/oplus/os/battery/not_restrict.xml 2>/dev/null | head -2

echo
echo "########## 2. THE FIX, PROVEN: thaw -> does the already-queued broadcast run? ##########"
input keyevent KEYCODE_HOME; sleep 5
echo 1 > $CF; sleep 2
echo "  step A: force frozen"; snap
D0=$(dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest $APKG")
echo "  step B: send broadcast while frozen (this is our current design)"
logcat -c 2>/dev/null
am broadcast -a com.islandbridge.KEEPALIVE -n $APKG/.KeepAliveReceiver >/dev/null 2>&1
sleep 3
D1=$(dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest $APKG")
echo "     deferred: $D0 -> $D1  (queued, not delivered)"; snap
echo "  step C: THAW the process (what a root relay / binder call does)"
echo 0 > $CF; sleep 4
echo "     after thaw:"; snap
D2=$(dumpsys activity broadcasts 2>/dev/null | grep -c "DEFERRED for manifest $APKG")
echo "     deferred now: $D2  (did the queue flush?)"
echo "     did our receiver actually run? (logcat):"
logcat -d -t 30 2>/dev/null | grep -iE "KeepAlive|islandbridge" | tail -5
echo "     (no log line = broadcast still not delivered)"

echo
echo "########## 3. The DELIVERY that DOES penetrate: binder from root ##########"
echo 1 > $CF; sleep 2; echo "  frozen:"; snap
su -c "content query --uri content://com.islandbridge.androidx-startup" >/dev/null 2>&1
sleep 2; echo "  after binder call into our app:"; snap
echo "  -> binder THAWS us. This is the channel to use instead of broadcast."

echo
echo "########## 4. system_server is the never-frozen vantage point we ALREADY own ##########"
echo "  our module loaded in: $(grep -ao '([a-z0-9._]*)\[com.islandbridge' /data/adb/lspd/log/modules_*.log 2>/dev/null | sort -u | tr '\n' ' ')"
echo "  uid_1000 freezable cgroup dir: $([ -d /sys/fs/cgroup/apps/uid_1000 ] && echo 'EXISTS' || echo 'NONE -> system_server CANNOT be frozen')"
echo "  systemui uid_10246 cgroup dir : $([ -d /sys/fs/cgroup/apps/uid_10246 ] && echo 'EXISTS (freeze='$(cat /sys/fs/cgroup/apps/uid_10246/cgroup.freeze 2>/dev/null)')' || echo NONE)"
echo "  astraflow(uid10050) cgroup dir: $([ -d /sys/fs/cgroup/apps/uid_10050 ] && echo EXISTS || echo 'NONE -> astraflow has NO process of its own; it lives inside SystemUI')"

input keyevent KEYCODE_HOME; sleep 1; echo 0 > $CF
