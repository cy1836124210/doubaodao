#!/system/bin/sh
# How does WeChat survive the freezer on THIS device?
# Hypothesis: OEM-whitelisted apps are never placed in a freezable cgroup at all.

echo "############ 1. Is WeChat / QQ / Alipay installed, and what uid? ############"
for p in com.tencent.mm com.tencent.mobileqq com.eg.android.AlipayGphone com.astraflow.tool com.islandbridge; do
  u=$(dumpsys package $p 2>/dev/null | grep -m1 "userId=" | tr -d ' ')
  echo "$p -> $u"
done

echo
echo "############ 2. Does each uid even HAVE a freezable cgroup dir? ############"
echo "(no dir = the system never freezes this uid)"
for u in 10370 10372 10246 10050; do
  if [ -d /sys/fs/cgroup/apps/uid_$u ]; then
    echo "uid_$u : EXISTS  freeze=$(cat /sys/fs/cgroup/apps/uid_$u/cgroup.freeze 2>/dev/null)  pids=$(ls /sys/fs/cgroup/apps/uid_$u/ 2>/dev/null | grep -c pid_)"
  else
    echo "uid_$u : NO CGROUP DIR  <-- immune to freezing"
  fi
done

echo
echo "############ 3. memory cgroup of each (apps/active = never frozen) ############"
for p in com.tencent.mm com.astraflow.tool com.islandbridge com.android.systemui; do
  pid=$(pidof $p 2>/dev/null | awk '{print $1}')
  if [ -n "$pid" ]; then
    echo "$p (pid $pid): $(grep memory /proc/$pid/cgroup 2>/dev/null)"
  else
    echo "$p : not running"
  fi
done

echo
echo "############ 4. OEM freeze whitelist files mentioning tencent ############"
for f in /system/etc/oplus_whitelist*.xml /system/etc/*whitelist* /data/oplus/os/*/*.xml; do
  [ -f "$f" ] && grep -l -i "tencent" "$f" 2>/dev/null
done 2>/dev/null | head -10
find /system/etc /data/oplus -maxdepth 4 -iname "*whitelist*" 2>/dev/null | head -20

echo
echo "############ 5. the OPLUS app-protection / preload list ############"
dumpsys activity 2>/dev/null | grep -iE "preload|protect|white" | head -15

echo
echo "############ 6. settings that whitelist apps ############"
settings list global 2>/dev/null | grep -iE "freez|protect|white|keepalive|startup" | head -15
settings list secure 2>/dev/null | grep -iE "freez|protect|white" | head -10

echo
echo "############ 7. Our app vs WeChat: isFrozen record line ############"
dumpsys activity processes 2>/dev/null | egrep -A1 "isFrozen=true" | egrep "com.tencent|com.islandbridge|Alipay" | head
echo "--- all currently isFrozen=true uids ---"
dumpsys activity processes 2>/dev/null | grep -oE "u0a[0-9]+" | sort -u | head -30

echo
echo "############ 8. Is WeChat's push process alive & in what cgroup? ############"
ps -A 2>/dev/null | grep -i tencent | head
