#!/system/bin/sh
echo "########## 1. Island-side: what did AstraIsland do with our frame? ##########"
logcat -d 2>/dev/null | grep -iE "AstraIsland|astraflow.*island|island.*(start|update|render|card)" | tail -25

echo
echo "########## 2. Island message history DB ##########"
DB=/data/user_de/0/com.android.systemui/cache/astraflow-island-message-history.sqlite
ls -l $DB 2>/dev/null
if [ -f "$DB" ]; then
  echo "  (needs sqlite3; checking for it)"
  which sqlite3 2>/dev/null || echo "  no sqlite3 on device"
  echo "  size/mtime: $(stat -c '%s %y' $DB 2>/dev/null)"
fi

echo
echo "########## 3. Is the app frozen again, and does the island session survive? ##########"
APKG=com.islandbridge
echo "  pid=[$(pidof $APKG)] freeze=[$(cat /sys/fs/cgroup/apps/uid_10370/cgroup.freeze 2>/dev/null)]"
logcat -d 2>/dev/null | grep -iE "session lost|onSessionLost|disconnect" | tail -5

echo
echo "########## 4. Current island state (dumpsys) ##########"
dumpsys activity service com.android.systemui 2>/dev/null | grep -iE "island|astraflow" | head -10 || echo "  (no island service dump)"
