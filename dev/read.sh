#!/system/bin/sh
SQ=/data/user_de/0/com.android.systemui/files/astraflow_sqlite3
for DB in \
  /data/user_de/0/com.android.systemui/cache/astraflow-island-message-history.sqlite \
  /data/user_de/0/com.android.systemui/cache/astraisland-message-history.sqlite ; do
  echo "===== $DB ====="
  ls -l "$DB" 2>/dev/null || { echo "  (absent)"; continue; }
  echo "  -- schema --"
  $SQ "$DB" "select name from sqlite_master where type='table';" 2>&1 | head -10
done

echo
echo "===== accessibility tree: can we read the island text? ====="
uiautomator dump /data/local/tmp/ui.xml >/dev/null 2>&1
if [ -f /data/local/tmp/ui.xml ]; then
  echo "  size: $(wc -c < /data/local/tmp/ui.xml)"
  echo "  nodes containing island-ish text:"
  tr '>' '>\n' < /data/local/tmp/ui.xml | grep -oE 'text="[^"]*"' | grep -v 'text=""' | head -25
else
  echo "  dump failed"
fi

echo
echo "===== dumpsys of the island window: any text? ====="
dumpsys window 2>/dev/null | grep -iE "AstraIsland" | head -6
