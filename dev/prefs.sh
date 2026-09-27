#!/system/bin/sh
echo "########## SystemUI shared_prefs files ##########"
ls -l /data/user_de/0/com.android.systemui/shared_prefs/ 2>/dev/null
ls -l /data/user/0/com.android.systemui/shared_prefs/ 2>/dev/null

echo
echo "########## island/astra-related prefs ##########"
for f in /data/user_de/0/com.android.systemui/shared_prefs/*.xml \
         /data/user/0/com.android.systemui/shared_prefs/*.xml ; do
  [ -f "$f" ] || continue
  if grep -qiE "astra|island" "$f" 2>/dev/null; then
    echo "=== $f ==="
    cat "$f" 2>/dev/null | head -60
    echo
  fi
done

echo
echo "########## any key mentioning width/scroll/marquee ##########"
for f in /data/user_de/0/com.android.systemui/shared_prefs/*.xml; do
  [ -f "$f" ] || continue
  grep -oiE 'name="[^"]*(width|scroll|marquee|led|lrc|max)[^"]*"[^/]*' "$f" 2>/dev/null | head -20
done
