#!/system/bin/sh
PORT=8799
LOG=/data/local/tmp/islandbridge_relay.log

echo "### 1. port listening? ###"
netstat -tlnp 2>/dev/null | grep ":$PORT" || echo "  NOT LISTENING"

echo
echo "### 2. inject RAW and watch ###"
: > $LOG
# what does printf actually emit? show it escaped
printf 'zqtok123\t{"t":"plan.start","tid":"dbg","title":"DBG"}\n' | od -c | head -3

echo
echo "### 3. send it ###"
printf 'zqtok123\t{"t":"plan.start","tid":"dbg","title":"DBG"}\n' | nc 127.0.0.1 $PORT
echo "  nc rc=$?"
sleep 3

echo
echo "### 4. log ###"
cat $LOG

echo
echo "### 5. port after ###"
netstat -tlnp 2>/dev/null | grep ":$PORT" || echo "  NOT LISTENING (listener died?)"

echo
echo "### 6. Is listen.sh still alive? ###"
for d in /proc/[0-9]*; do
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge/listen*) echo "  ${d#/proc/}: $c" ;; esac
done
