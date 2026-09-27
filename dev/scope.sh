#!/system/bin/sh
echo "########## 1. Our module's LSPosed SCOPE ##########"
d=/data/adb/lspd/config
ls -la $d 2>/dev/null
for f in $d/*.db; do echo "  found $f"; done

echo
echo "########## 2. Is SystemUI in our scope? (module scope from log) ##########"
L=/data/adb/lspd/log
ls -t $L/modules_*.log 2>/dev/null | head -1 | while read f; do
  echo "  --- modules loaded per process (from $(basename $f)) ---"
  grep -ao "(com.android.systemui)\[com.islandbridge" "$f" | head -3
  grep -ao "(system)\[com.islandbridge" "$f" | head -2
  grep -ao "(com.larus.nova)\[com.islandbridge" "$f" | head -2
  echo "  --- distinct processes our module loaded into ---"
  grep -ao "([a-z0-9._]*)\[com.islandbridge" "$f" | sort -u
done

echo
echo "########## 3. AstraIsland's registered services INSIDE SystemUI ##########"
dumpsys activity services com.android.systemui 2>/dev/null | grep -iE "astra|island" | head -10
echo "  --- total services in systemui ---"
dumpsys activity services com.android.systemui 2>/dev/null | grep -c "ServiceRecord"

echo
echo "########## 4. Does SystemUI expose the island over binder to others? ##########"
dumpsys activity providers 2>/dev/null | grep -iE "astra|island" | head -5
echo "  (empty = island has NO provider/service face; it is purely in-process)"

echo
echo "########## 5. Confirm: SystemUI is where island state lives ##########"
ls -la /data/user_de/0/com.android.systemui/cache/ 2>/dev/null | grep -i astra
echo "  --- all astraflow files owned by systemui ---"
find /data/user_de/0/com.android.systemui -iname "*astra*" 2>/dev/null | head

echo
echo "########## 6. What does the island host use to draw (Compose in SystemUI)? ##########"
echo "  astraflow render classes are com.astraisland.render.compose.* (obfuscated)"
echo "  -> confirm compose present in SystemUI's loaded dex:"
grep -ac "androidx/compose" /data/adb/lspd/log/modules_*.log 2>/dev/null | head -1

echo
echo "########## 7. Our module DLL/scope currently attached to: ##########"
grep -a "islandbridge" /data/adb/lspd/log/modules_*.log 2>/dev/null | grep -ao "^\[[^]]*\][^)]*)" | sed 's/.*(\([^)]*\))/\1/' | sort -u | head
