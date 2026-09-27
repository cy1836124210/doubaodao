#!/system/bin/sh
echo "########## 1. nc capabilities ##########"
echo "  system nc: $(which nc)"
nc --help 2>&1 | head -20
echo "  --- busybox nc ---"
/data/adb/ksu/bin/busybox nc --help 2>&1 | head -20

echo
echo "########## 2. Does 'nc -l -k' (keep listening) work? ##########"
/data/adb/ksu/bin/busybox nc -l -k -p 8899 >/data/local/tmp/k.log 2>&1 &
KP=$!
sleep 1
i=1
while [ $i -le 5 ]; do
  printf 'line%s\n' $i | /data/adb/ksu/bin/busybox nc 127.0.0.1 8899
  i=$((i+1))
done
sleep 1
echo "  received:"; cat /data/local/tmp/k.log
kill -9 $KP 2>/dev/null

echo
echo "########## 3. Does toybox 'nc -l -p' survive multiple connects? ##########"
/system/bin/nc -l -p 8898 >/data/local/tmp/t.log 2>&1 &
TP=$!
sleep 1
i=1
while [ $i -le 5 ]; do
  printf 'line%s\n' $i | /system/bin/nc 127.0.0.1 8898
  i=$((i+1))
done
sleep 1
echo "  received:"; cat /data/local/tmp/t.log
kill -9 $TP 2>/dev/null
