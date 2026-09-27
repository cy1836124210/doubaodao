#!/system/bin/sh
echo "########## 1. OPPO not_restrict.xml (the 'never freeze' list) ##########"
ls -la /data/oplus/os/battery/not_restrict.xml 2>/dev/null
echo "--- packages on it (tencent/wechat family) ---"
grep -o 'att="[^"]*"' /data/oplus/os/battery/not_restrict.xml 2>/dev/null | sed 's/att="//;s/"//' | head -30
echo "--- is OUR app on it? ---"
grep -c 'com.islandbridge' /data/oplus/os/battery/not_restrict.xml 2>/dev/null
echo "--- is Doubao? ---"
grep -c 'com.larus.nova' /data/oplus/os/battery/not_restrict.xml 2>/dev/null

echo
echo "########## 2. startinfo_white.xml (autostart allowed) ##########"
grep -o 'att="[^"]*"' /data/oplus/os/battery/startinfo_white.xml 2>/dev/null | sed 's/att="//;s/"//' | head -20
echo "our app on it: $(grep -c 'com.islandbridge' /data/oplus/os/battery/startinfo_white.xml 2>/dev/null)"

echo
echo "########## 3. Is the whitelist writable (root fix possible)? ##########"
ls -la /data/oplus/os/battery/ 2>/dev/null | head -20

echo
echo "########## 4. WeChat vs us: same freeze, different whitelist ##########"
for p in com.tencent.mm com.islandbridge; do
  echo "=== $p ==="
  echo "   not_restrict: $(grep -c "$p" /data/oplus/os/battery/not_restrict.xml 2>/dev/null)"
  echo "   doze_wl_local: $(grep -c "$p" /data/oplus/os/battery/doze_wl_local.xml 2>/dev/null)"
  echo "   notify_whitelist: $(grep -c "$p" /data/oplus/os/battery/notify_whitelist.xml 2>/dev/null)"
  pid=$(pidof $p 2>/dev/null | awk '{print $1}')
  [ -n "$pid" ] && echo "   wchan: $(cat /proc/$pid/wchan 2>/dev/null)  cgroup: $(grep memory /proc/$pid/cgroup 2>/dev/null)"
done

echo
echo "########## 5. What a 3rd-party app can use that ISN'T a broadcast ##########"
echo "--- does our app declare any binder service / provider reachable from outside? ---"
dumpsys package com.islandbridge 2>/dev/null | sed -n '/Service Resolver Table/,/Receiver Resolver Table/p' | head -20
echo "--- providers ---"
dumpsys package com.islandbridge 2>/dev/null | sed -n '/ContentProvider Resolver Table/,/^$/p' | head -20
