#!/system/bin/sh
BB=/data/adb/ksu/bin/busybox
cat > /data/local/tmp/handle.sh <<'EOF'
#!/system/bin/sh
while IFS= read -r line; do
  echo "got:$line"
done
EOF
chmod 755 /data/local/tmp/handle.sh

echo "########## busybox nc -lk -e handler (persistent forking server) ##########"
rm -f /data/local/tmp/e.log
$BB nc -lk -p 8896 -e /data/local/tmp/handle.sh >/data/local/tmp/e.log 2>&1 &
EP=$!
sleep 1
i=1
while [ $i -le 6 ]; do
  printf 'line%s\n' $i | $BB nc 127.0.0.1 8896
  i=$((i+1))
done
sleep 2
echo "  received $(grep -c got: /data/local/tmp/e.log) / 6 lines:"
cat /data/local/tmp/e.log
echo "  server alive: $([ -d /proc/$EP ] && echo YES || echo NO)"
kill -9 $EP 2>/dev/null
$BB pkill -f "nc -lk -p 8896" 2>/dev/null
