#!/system/bin/sh
APKG=com.islandbridge
echo "### Is chat.start actually failing, or just log-rotated away? ###"
echo "  total log lines mentioning chat.start: $(logcat -d 2>/dev/null | grep -c 'chat.start')"
echo "  app-pipeline lines for m9:"
logcat -d 2>/dev/null | grep -E "IslandBridge" | grep -E "m9|START|card|岛" | head -20
echo
echo "### full app pipeline since this run (non-delta) ###"
logcat -d 2>/dev/null | grep -E "IslandBridge:" | grep -v "provider ev" | grep -v "chat.delta" | head -20
echo
echo "### island pill ###"
dumpsys window 2>/dev/null | grep -o 'AstraIsland, frame=\[Rect(0, 0 - 1440, 760)\], touchableRegion=SkRegion([^)]*)' | head -1
