#!/system/bin/sh
echo "########## 1. Did service.d run at boot? ##########"
cat /data/local/tmp/marker.log 2>/dev/null || echo "  NO marker.log -> service.d did NOT execute"

echo
echo "########## 2. Are the helpers alive? (authoritative /proc scan) ##########"
for d in /proc/[0-9]*; do
  p=${d#/proc/}
  c=$(tr '\0' ' ' < $d/cmdline 2>/dev/null)
  case "$c" in *islandbridge_relay*|*islandbridge_listen*|*ib_relay*) echo "  $p: $c" ;; esac
done
echo "  pidfile: [$(cat /data/data/com.islandbridge/files/ib_relay.pid 2>/dev/null)]"

echo
echo "########## 3. Listener port open? ##########"
PORT=$(cat /data/data/com.islandbridge/files/ib_listen.port 2>/dev/null)
[ -z "$PORT" ] && PORT=8799
echo "  configured port = $PORT"
netstat -tlnp 2>/dev/null | grep ":$PORT" || ss -tlnp 2>/dev/null | grep ":$PORT" || echo "  (no netstat/ss match)"

echo
echo "########## 4. Relay log ##########"
tail -20 /data/local/tmp/islandbridge_relay.log 2>/dev/null || echo "  no log"

echo
echo "########## 5. nc capability ##########"
echo "  nc: $(which nc 2>/dev/null)"
nc -h 2>&1 | head -6
